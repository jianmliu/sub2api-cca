// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { ISubscriptionPredicate } from "../src/interfaces/ISubscriptionPredicate.sol";

contract ConfigureAIGGSubscriptionPredicate is Script {
    uint256 private constant BASE_CHAIN_ID = 8453;

    error InvalidMinTier(uint256 minTier);
    error WrongChain(uint256 chainId);

    function run() external {
        _requireBaseChain();

        ISubscriptionPredicate predicate = ISubscriptionPredicate(
            vm.envOr(
                "ERC8257_SUBSCRIPTION_PREDICATE",
                address(0xCBe0cd9B1d99d95Baa9c58f2767246C52e461f25)
            )
        );
        uint256 toolId = vm.envUint("AIGG_TOOL_ID");
        address pass = vm.envAddress("AIGG_SUBSCRIPTION_PASS");
        uint256 minTierValue = vm.envOr("AIGG_MIN_SUBSCRIPTION_TIER", uint256(1));
        if (minTierValue == 0 || minTierValue > type(uint8).max) {
            revert InvalidMinTier(minTierValue);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 minTier = uint8(minTierValue);

        vm.startBroadcast();
        predicate.configureToolGating(toolId, pass, minTier);
        vm.stopBroadcast();

        console2.log("tool id:", toolId);
        console2.log("subscription pass:", pass);
        console2.log("min tier:", minTier);
    }

    function _requireBaseChain() private view {
        bool allowNonBase = vm.envOr("ALLOW_NON_BASE_ERC8257", false);
        if (block.chainid != BASE_CHAIN_ID && !allowNonBase) revert WrongChain(block.chainid);
    }
}
