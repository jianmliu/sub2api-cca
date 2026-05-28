// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { GCC } from "../src/GCC.sol";
import { GCCCCAToV4Seeder, IV4PoolManager, IV4PositionManager } from "../src/GCCCCAToV4Seeder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Mock USDC — 6-decimal stand-in. Forge has no built-in USDC fixture.
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin (mock)", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Records `initialize` calls so the seeder test can assert on them.
contract MockPoolManager is IV4PoolManager {
    PoolKey public lastKey;
    uint160 public lastSqrtPrice;
    uint256 public initializeCalls;
    int24 public nextTick;
    bool public shouldRevert;

    function setShouldRevert(bool flag) external {
        shouldRevert = flag;
    }

    function setNextTick(int24 t) external {
        nextTick = t;
    }

    function initialize(PoolKey calldata key, uint160 sqrtPriceX96)
        external
        override
        returns (int24)
    {
        if (shouldRevert) revert("MockPoolManager: forced revert");
        lastKey = key;
        lastSqrtPrice = sqrtPriceX96;
        initializeCalls++;
        return nextTick;
    }
}

/// @dev Records multicall payloads + pulls token balances to simulate the
///      real PositionManager's behaviour (settle pair → tokens move from
///      caller to manager). We don't simulate LP NFT minting since the
///      seeder doesn't introspect it.
contract MockPositionManager is IV4PositionManager {
    address public usdc;
    address public gcc;
    bytes[] public lastCallData;
    uint256 public multicallCalls;

    constructor(address usdc_, address gcc_) {
        usdc = usdc_;
        gcc = gcc_;
    }

    function multicall(bytes[] calldata data)
        external
        payable
        override
        returns (bytes[] memory)
    {
        multicallCalls++;
        delete lastCallData;
        for (uint256 i; i < data.length; i++) {
            lastCallData.push(data[i]);
        }
        // Simulate "settle pair" by pulling caller's full balance of each
        // token via Permit2 (matching the real V4 PositionManager — direct
        // ERC-20 transferFrom from a non-permit2-pre-approved owner would
        // revert in the real contract too).
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        uint256 usdcBal = IERC20(usdc).balanceOf(msg.sender);
        if (usdcBal > 0) {
            IStubPermit2(permit2).transferFrom(msg.sender, address(this), uint160(usdcBal), usdc);
        }
        uint256 gccBal = IERC20(gcc).balanceOf(msg.sender);
        if (gccBal > 0) {
            IStubPermit2(permit2).transferFrom(msg.sender, address(this), uint160(gccBal), gcc);
        }
        bytes[] memory results = new bytes[](data.length);
        return results;
    }
}

interface IStubPermit2 {
    function transferFrom(address from, address to, uint160 amount, address token) external;
}

/// @dev Stub Permit2 — only the two methods the seeder touches. Accepts
///      any approve and lets transferFrom call straight through to ERC20.
///      In real Permit2 these are gated by allowances; the stub gates
///      nothing so tests can focus on the seeder, not the Permit2 contract.
contract StubPermit2 {
    function approve(address, address, uint160, uint48) external pure {}

    function transferFrom(address from, address to, uint160 amount, address token) external {
        require(IERC20(token).transferFrom(from, to, amount), "stub permit2: transfer failed");
    }
}

contract GCCCCAToV4SeederTest is Test {
    GCC private gcc;
    MockUSDC private usdc;
    MockPoolManager private pm;
    MockPositionManager private posm;
    GCCCCAToV4Seeder private seeder;

    address private constant TREASURY = address(0xCAFE);
    address private constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint24 private constant POOL_FEE = 3000;
    int24 private constant TICK_SPACING = 60;

    bytes[] private emptyActions;

    function setUp() public {
        // Deploy a stub at the canonical Permit2 address. The seeder
        // hard-codes that address (constant) so we have to plant the
        // stub there rather than thread an injected address through.
        StubPermit2 stub = new StubPermit2();
        vm.etch(PERMIT2, address(stub).code);

        gcc = new GCC("Guaranteed Capacity Credit", "GCC", address(this), 0, 1_000_000_000 ether);
        usdc = new MockUSDC();
        pm = new MockPoolManager();
        posm = new MockPositionManager(address(usdc), address(gcc));
        seeder = new GCCCCAToV4Seeder({
            gcc_: address(gcc),
            usdc_: address(usdc),
            poolManager_: address(pm),
            positionManager_: address(posm),
            poolFee_: POOL_FEE,
            tickSpacing_: TICK_SPACING,
            owner_: TREASURY
        });
    }

    function testBootstrapInitialisesPoolWithCanonicallySortedKey() public {
        gcc.mint(address(seeder), 200_000 ether);
        usdc.mint(address(seeder), 60_000 * 1e6);

        vm.prank(TREASURY);
        seeder.bootstrap(_dummySqrt(), -887_220, 887_220, _twoActionPayload());

        IV4PoolManager.PoolKey memory key = _readPoolKey();
        // currency0 must be the lower address; check ordering matches addresses.
        if (address(usdc) < address(gcc)) {
            assertEq(key.currency0, address(usdc));
            assertEq(key.currency1, address(gcc));
        } else {
            assertEq(key.currency0, address(gcc));
            assertEq(key.currency1, address(usdc));
        }
        assertEq(uint256(key.fee), POOL_FEE);
        assertEq(int256(key.tickSpacing), int256(TICK_SPACING));
        assertEq(key.hooks, address(0));
        assertTrue(seeder.initialized());
    }

    function testBootstrapTransfersAllBalancesToPositionManager() public {
        gcc.mint(address(seeder), 200_000 ether);
        usdc.mint(address(seeder), 60_000 * 1e6);

        vm.prank(TREASURY);
        seeder.bootstrap(_dummySqrt(), -887_220, 887_220, _twoActionPayload());

        // PositionManager's mock implementation pulls the full balance via
        // transferFrom; both should be drained from the seeder.
        assertEq(gcc.balanceOf(address(seeder)), 0);
        assertEq(usdc.balanceOf(address(seeder)), 0);
        assertEq(gcc.balanceOf(address(posm)), 200_000 ether);
        assertEq(usdc.balanceOf(address(posm)), 60_000 * 1e6);
    }

    function testBootstrapClearsApprovals() public {
        gcc.mint(address(seeder), 100 ether);
        usdc.mint(address(seeder), 50 * 1e6);

        vm.prank(TREASURY);
        seeder.bootstrap(_dummySqrt(), -887_220, 887_220, _twoActionPayload());

        assertEq(gcc.allowance(address(seeder), address(posm)), 0);
        assertEq(usdc.allowance(address(seeder), address(posm)), 0);
    }

    function testBootstrapRevertsIfNotOwner() public {
        gcc.mint(address(seeder), 100 ether);
        usdc.mint(address(seeder), 50 * 1e6);

        vm.expectRevert();
        seeder.bootstrap(_dummySqrt(), -887_220, 887_220, _twoActionPayload());
    }

    function testBootstrapRevertsIfNoLiquidity() public {
        // GCC is present but USDC is not.
        gcc.mint(address(seeder), 100 ether);

        vm.prank(TREASURY);
        vm.expectRevert(GCCCCAToV4Seeder.NoLiquidity.selector);
        seeder.bootstrap(_dummySqrt(), -887_220, 887_220, _twoActionPayload());
    }

    function testBootstrapRevertsOnInvalidTickRange() public {
        gcc.mint(address(seeder), 100 ether);
        usdc.mint(address(seeder), 50 * 1e6);

        vm.prank(TREASURY);
        vm.expectRevert(GCCCCAToV4Seeder.InvalidTickRange.selector);
        seeder.bootstrap(_dummySqrt(), 60, -60, _twoActionPayload());
    }

    function testBootstrapRevertsOnTickNotAligned() public {
        gcc.mint(address(seeder), 100 ether);
        usdc.mint(address(seeder), 50 * 1e6);

        vm.prank(TREASURY);
        vm.expectRevert(GCCCCAToV4Seeder.TickNotAligned.selector);
        seeder.bootstrap(_dummySqrt(), -100, 60, _twoActionPayload());
    }

    function testBootstrapCannotBeRunTwice() public {
        gcc.mint(address(seeder), 100 ether);
        usdc.mint(address(seeder), 50 * 1e6);

        vm.prank(TREASURY);
        seeder.bootstrap(_dummySqrt(), -887_220, 887_220, _twoActionPayload());

        // GCC.mint requires the test contract as owner; switch out of the
        // TREASURY prank to top the seeder up for the second-shot attempt.
        gcc.mint(address(seeder), 100 ether);
        usdc.mint(address(seeder), 50 * 1e6);

        vm.prank(TREASURY);
        vm.expectRevert(GCCCCAToV4Seeder.AlreadyInitialized.selector);
        seeder.bootstrap(_dummySqrt(), -887_220, 887_220, _twoActionPayload());
    }

    function testAddLiquidityRequiresInitialisedPool() public {
        gcc.mint(address(seeder), 100 ether);
        usdc.mint(address(seeder), 50 * 1e6);

        vm.prank(TREASURY);
        vm.expectRevert(GCCCCAToV4Seeder.NotInitialized.selector);
        seeder.addLiquidity(-887_220, 887_220, _twoActionPayload());
    }

    function testAddLiquidityCanBeCalledRepeatedlyAfterBootstrap() public {
        gcc.mint(address(seeder), 200 ether);
        usdc.mint(address(seeder), 100 * 1e6);

        vm.prank(TREASURY);
        seeder.bootstrap(_dummySqrt(), -887_220, 887_220, _twoActionPayload());
        assertEq(pm.initializeCalls(), 1);

        // Subsequent CCA round: re-fund + add liquidity. Pool isn't
        // re-initialised (would revert in the mock if it were).
        gcc.mint(address(seeder), 50 ether);
        usdc.mint(address(seeder), 25 * 1e6);

        vm.prank(TREASURY);
        seeder.addLiquidity(-887_220, 887_220, _twoActionPayload());
        assertEq(pm.initializeCalls(), 1, "initialize should NOT be called again");
        assertEq(posm.multicallCalls(), 2, "should have minted two LP positions");

        // Third CCA round.
        gcc.mint(address(seeder), 30 ether);
        usdc.mint(address(seeder), 15 * 1e6);

        vm.prank(TREASURY);
        seeder.addLiquidity(-887_220, 887_220, _twoActionPayload());
        assertEq(pm.initializeCalls(), 1);
        assertEq(posm.multicallCalls(), 3);
    }

    function testAddLiquidityRequiresOwner() public {
        gcc.mint(address(seeder), 100 ether);
        usdc.mint(address(seeder), 50 * 1e6);

        vm.prank(TREASURY);
        seeder.bootstrap(_dummySqrt(), -887_220, 887_220, _twoActionPayload());

        gcc.mint(address(seeder), 50 ether);
        usdc.mint(address(seeder), 25 * 1e6);

        vm.expectRevert();
        seeder.addLiquidity(-887_220, 887_220, _twoActionPayload());
    }

    function testAddLiquidityRespectsTickValidation() public {
        gcc.mint(address(seeder), 100 ether);
        usdc.mint(address(seeder), 50 * 1e6);

        vm.prank(TREASURY);
        seeder.bootstrap(_dummySqrt(), -887_220, 887_220, _twoActionPayload());

        gcc.mint(address(seeder), 50 ether);
        usdc.mint(address(seeder), 25 * 1e6);

        vm.prank(TREASURY);
        vm.expectRevert(GCCCCAToV4Seeder.TickNotAligned.selector);
        seeder.addLiquidity(-100, 60, _twoActionPayload());
    }

    function testRecoverSweepsArbitraryERC20() public {
        gcc.mint(address(seeder), 42 ether);

        vm.prank(TREASURY);
        seeder.recover(address(gcc), TREASURY, 42 ether);

        assertEq(gcc.balanceOf(TREASURY), 42 ether);
        assertEq(gcc.balanceOf(address(seeder)), 0);
    }

    function testRecoverRejectsNonOwner() public {
        gcc.mint(address(seeder), 42 ether);

        vm.expectRevert();
        seeder.recover(address(gcc), address(this), 42 ether);
    }

    // ── helpers ───────────────────────────────────────────────────────────

    function _readPoolKey() private view returns (IV4PoolManager.PoolKey memory key) {
        (key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks) = pm.lastKey();
    }

    function _dummySqrt() private pure returns (uint160) {
        // 1.0 in Q64.96. Arbitrary — we don't read it back in these tests.
        return 79_228_162_514_264_337_593_543_950_336;
    }

    function _twoActionPayload() private pure returns (bytes[] memory data) {
        data = new bytes[](2);
        data[0] = hex"00";
        data[1] = hex"01";
    }
}
