// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { GCT } from "../src/GCT.sol";

contract DeployGCT is Script {
    function run() external returns (GCT token) {
        string memory name = vm.envOr("GCT_NAME", string("Guaranteed Capacity Token"));
        string memory symbol = vm.envOr("GCT_SYMBOL", string("GCT"));
        address initialRecipient = vm.envOr("GCT_INITIAL_RECIPIENT", msg.sender);
        uint256 initialSupply = vm.envOr("GCT_INITIAL_SUPPLY", uint256(0));

        vm.startBroadcast();
        token = new GCT(name, symbol, initialRecipient, initialSupply);
        vm.stopBroadcast();

        console2.log("GCT token:", address(token));
        console2.log("owner:", token.owner());
    }
}
