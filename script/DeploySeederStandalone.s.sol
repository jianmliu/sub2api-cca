// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { GCCCCAToV4Seeder } from "../src/GCCCCAToV4Seeder.sol";

/// @notice Deploy a fresh GCCCCAToV4Seeder pointed at the same GCC / V4
///         addresses as the rest of the CCA stack. Used when an existing
///         seeder is being replaced (e.g. a bug fix) but the V4 pool is
///         already initialised — the new seeder calls `adoptInitializedPool`
///         after deploy and then accumulates funds for `addLiquidity`.
///
///         Env vars (all required):
///           GCC_TOKEN                 GCC ERC-20 address
///           CCA_V4_USDC               USDC ERC-20 address
///           CCA_V4_POOL_MANAGER       Uniswap V4 PoolManager
///           CCA_V4_POSITION_MANAGER   Uniswap V4 PositionManager
///           CCA_V4_POOL_FEE           fee tier (uint24)
///           CCA_V4_TICK_SPACING       tick spacing (int24)
///           CCA_V4_TREASURY           seeder owner (LP NFT recipient)
///           CCA_V4_ADOPT_EXISTING_POOL  if "true", also calls
///                                       adoptInitializedPool() after deploy.
contract DeploySeederStandalone is Script {
    function run() external returns (address seederAddr) {
        address gccToken = vm.envAddress("GCC_TOKEN");
        address usdc = vm.envAddress("CCA_V4_USDC");
        address pm = vm.envAddress("CCA_V4_POOL_MANAGER");
        address posm = vm.envAddress("CCA_V4_POSITION_MANAGER");
        uint24 fee = uint24(vm.envOr("CCA_V4_POOL_FEE", uint256(3000)));
        int24 spacing = int24(vm.envOr("CCA_V4_TICK_SPACING", int256(60)));
        address treasury = vm.envAddress("CCA_V4_TREASURY");
        bool adoptExisting = vm.envOr("CCA_V4_ADOPT_EXISTING_POOL", false);

        vm.startBroadcast();
        GCCCCAToV4Seeder seeder =
            new GCCCCAToV4Seeder(gccToken, usdc, pm, posm, fee, spacing, treasury);
        if (adoptExisting && treasury == msg.sender) {
            // Only auto-adopt when the broadcasting key IS the owner — for
            // multisigs the adopt call has to come from a queued tx instead.
            seeder.adoptInitializedPool();
        }
        vm.stopBroadcast();

        seederAddr = address(seeder);
        console2.log("seeder:", seederAddr);
        console2.log("owner:", treasury);
        console2.log("adopted existing pool:", adoptExisting && treasury == msg.sender);
    }
}
