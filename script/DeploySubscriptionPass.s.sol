// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { SubscriptionPass } from "../src/SubscriptionPass.sol";

contract DeploySubscriptionPass is Script {
    uint256 private constant BASE_CHAIN_ID = 8453;

    error WrongChain(uint256 chainId);

    function run() external returns (address pass) {
        _requireBaseChain();

        string memory name = vm.envOr("SUBSCRIPTION_PASS_NAME", string("AI.GG Subscription Pass"));
        string memory symbol = vm.envOr("SUBSCRIPTION_PASS_SYMBOL", string("AIGG-SUB"));
        address owner = vm.envAddress("SUBSCRIPTION_PASS_OWNER");

        vm.startBroadcast();
        pass = address(new SubscriptionPass(name, symbol, owner));
        vm.stopBroadcast();

        console2.log("subscription pass:", pass);
        console2.log("owner:", owner);
    }

    function _requireBaseChain() private view {
        bool allowNonBase = vm.envOr("ALLOW_NON_BASE_ERC8257", false);
        if (block.chainid != BASE_CHAIN_ID && !allowNonBase) revert WrongChain(block.chainid);
    }
}
