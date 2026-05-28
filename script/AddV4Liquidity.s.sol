// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GCCCCAToV4Seeder } from "../src/GCCCCAToV4Seeder.sol";

import { Actions } from "v4-periphery/src/libraries/Actions.sol";
import { LiquidityAmounts } from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { Currency } from "v4-core/src/types/Currency.sol";
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";
import { TickMath } from "v4-core/src/libraries/TickMath.sol";
import { StateLibrary } from "v4-core/src/libraries/StateLibrary.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";

/// @notice Builds the v4-periphery `Actions` calldata for MINT_POSITION +
///         SETTLE_PAIR, then forwards it to the seeder's `bootstrap` (first
///         CCA round) or `addLiquidity` (subsequent rounds) entry point.
///
/// @dev    Reads pool state from the V4 PoolManager via StateLibrary so the
///         on-chain `sqrtPriceX96` drives the liquidity calculation. Token
///         balances are read directly from the seeder. The script is
///         **balance-greedy**: it asks the PositionManager to mint a single
///         full-range position consuming as much USDC + GCC as the seeder
///         currently holds, leaving only rounding dust behind.
///
///         Env vars consumed:
///           CCA_V4_SEEDER       — required: seeder contract address
///           CCA_V4_POOL_MANAGER — required: PoolManager (for state reads)
///           CCA_V4_USDC         — required: pool currency0/currency1 (we sort)
///           CCA_V4_GCC          — required: pool currency1/currency0
///           CCA_V4_POOL_FEE     — default 3000
///           CCA_V4_TICK_SPACING — default 60
///           CCA_V4_HOOKS        — default address(0)
///           CCA_V4_DEADLINE_SEC — default 1800 (30 min from broadcast)
///           CCA_V4_USE_BOOTSTRAP — if "true", call `bootstrap(...)` with
///                                  the pool's sqrtPrice as the seed; else
///                                  call `addLiquidity(...)` (default).
contract AddV4Liquidity is Script {
    using StateLibrary for IPoolManager;

    int24 internal constant FULL_RANGE_TICK_LOWER = -887_220;
    int24 internal constant FULL_RANGE_TICK_UPPER = 887_220;

    struct Inputs {
        GCCCCAToV4Seeder seeder;
        IPoolManager poolManager;
        address usdc;
        address gcc;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        uint256 deadlineSec;
        bool useBootstrap;
    }

    function run() external {
        Inputs memory in_ = _readEnv();
        PoolKey memory key = _buildPoolKey(in_);
        uint160 sqrtPriceX96 = _resolveSqrtPrice(in_, key);

        (uint256 amount0, uint256 amount1) = _readBalances(in_, key);
        uint128 liquidity = _computeLiquidity(sqrtPriceX96, amount0, amount1, in_.tickSpacing);

        bytes[] memory multicallData = _buildMulticall(key, liquidity, amount0, amount1, in_);

        _logSummary(in_, sqrtPriceX96, amount0, amount1, liquidity);

        vm.startBroadcast();
        if (in_.useBootstrap) {
            in_.seeder.bootstrap(
                sqrtPriceX96, FULL_RANGE_TICK_LOWER, FULL_RANGE_TICK_UPPER, multicallData
            );
        } else {
            in_.seeder.addLiquidity(FULL_RANGE_TICK_LOWER, FULL_RANGE_TICK_UPPER, multicallData);
        }
        vm.stopBroadcast();

        console2.log("== DONE ==");
    }

    function _readEnv() internal view returns (Inputs memory in_) {
        in_.seeder = GCCCCAToV4Seeder(payable(vm.envAddress("CCA_V4_SEEDER")));
        in_.poolManager = IPoolManager(vm.envAddress("CCA_V4_POOL_MANAGER"));
        in_.usdc = vm.envAddress("CCA_V4_USDC");
        in_.gcc = vm.envAddress("CCA_V4_GCC");
        in_.fee = uint24(vm.envOr("CCA_V4_POOL_FEE", uint256(3000)));
        in_.tickSpacing = int24(vm.envOr("CCA_V4_TICK_SPACING", int256(60)));
        in_.hooks = vm.envOr("CCA_V4_HOOKS", address(0));
        in_.deadlineSec = vm.envOr("CCA_V4_DEADLINE_SEC", uint256(1800));
        in_.useBootstrap = vm.envOr("CCA_V4_USE_BOOTSTRAP", false);
    }

    function _buildPoolKey(Inputs memory in_) internal pure returns (PoolKey memory key) {
        (address c0Addr, address c1Addr) =
            in_.usdc < in_.gcc ? (in_.usdc, in_.gcc) : (in_.gcc, in_.usdc);
        key = PoolKey({
            currency0: Currency.wrap(c0Addr),
            currency1: Currency.wrap(c1Addr),
            fee: in_.fee,
            tickSpacing: in_.tickSpacing,
            hooks: IHooks(in_.hooks)
        });
    }

    function _resolveSqrtPrice(Inputs memory in_, PoolKey memory key)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        if (in_.useBootstrap) {
            // bootstrap initialises the pool itself; the caller supplies the
            // seed price via CCA_V4_SQRT_PRICE_X96.
            sqrtPriceX96 = uint160(vm.envUint("CCA_V4_SQRT_PRICE_X96"));
        } else {
            (sqrtPriceX96,,,) = in_.poolManager.getSlot0(key.toId());
            require(sqrtPriceX96 > 0, "pool not initialised; use bootstrap mode");
        }
    }

    function _readBalances(Inputs memory in_, PoolKey memory key)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        amount0 = IERC20(Currency.unwrap(key.currency0)).balanceOf(address(in_.seeder));
        amount1 = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(in_.seeder));
        require(amount0 > 0 && amount1 > 0, "seeder has no balance to LP");
    }

    function _computeLiquidity(
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1,
        int24 tickSpacing
    ) internal pure returns (uint128 liquidity) {
        require(
            FULL_RANGE_TICK_LOWER % tickSpacing == 0
                && FULL_RANGE_TICK_UPPER % tickSpacing == 0,
            "tick not aligned"
        );
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(FULL_RANGE_TICK_LOWER);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(FULL_RANGE_TICK_UPPER);
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1
        );
        require(liquidity > 0, "computed liquidity is zero");
    }

    /// @dev Encode the v4-periphery actions calldata and wrap it for
    ///      PositionManager.multicall.
    ///
    ///      The seeder forwards a `bytes[]` straight to
    ///      `PositionManager.multicall`. We need exactly one multicall entry:
    ///      a call to `modifyLiquidities(bytes unlockData, uint256 deadline)`
    ///      whose unlockData = abi.encode(actions, params).
    ///
    ///        actions = packed (uint8 MINT_POSITION) ++ (uint8 SETTLE_PAIR)
    ///        params[0] = abi.encode(PoolKey, tickLower, tickUpper, liquidity,
    ///                               amount0Max, amount1Max, owner, hookData)
    ///        params[1] = abi.encode(Currency currency0, Currency currency1)
    function _buildMulticall(
        PoolKey memory key,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1,
        Inputs memory in_
    ) internal view returns (bytes[] memory multicallData) {
        bytes memory actions =
            abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key,
            FULL_RANGE_TICK_LOWER,
            FULL_RANGE_TICK_UPPER,
            uint256(liquidity),
            uint128(amount0),     // amount0Max
            uint128(amount1),     // amount1Max
            in_.seeder.owner(),   // LP NFT recipient = treasury
            bytes("")             // empty hookData
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        bytes memory unlockData = abi.encode(actions, params);
        uint256 deadline = block.timestamp + in_.deadlineSec;
        bytes4 modifyLiqSel = bytes4(keccak256("modifyLiquidities(bytes,uint256)"));

        multicallData = new bytes[](1);
        multicallData[0] = abi.encodeWithSelector(modifyLiqSel, unlockData, deadline);
    }

    function _logSummary(
        Inputs memory in_,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1,
        uint128 liquidity
    ) internal view {
        console2.log("== AddV4Liquidity ==");
        console2.log("seeder:", address(in_.seeder));
        console2.log("poolManager:", address(in_.poolManager));
        console2.log("sqrtPriceX96:", uint256(sqrtPriceX96));
        console2.log("amount0 (currency0):", amount0);
        console2.log("amount1 (currency1):", amount1);
        console2.log("liquidity:", uint256(liquidity));
        console2.log("tickLower:", int256(FULL_RANGE_TICK_LOWER));
        console2.log("tickUpper:", int256(FULL_RANGE_TICK_UPPER));
        console2.log("useBootstrap:", in_.useBootstrap);
    }
}
