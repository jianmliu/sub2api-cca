// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { GCC } from "../src/GCC.sol";

contract DeployGCC is Script {
    function run() external returns (GCC token) {
        string memory name = vm.envOr("GCC_NAME", string("Guaranteed Capacity Credit"));
        string memory symbol = vm.envOr("GCC_SYMBOL", string("GCC"));
        address initialRecipient = vm.envOr("GCC_INITIAL_RECIPIENT", msg.sender);
        uint256 initialSupply = vm.envOr("GCC_INITIAL_SUPPLY", uint256(0));
        uint256 maxSupply = vm.envOr("GCC_MAX_SUPPLY", uint256(1_000_000_000 ether));

        vm.startBroadcast();
        token = new GCC(name, symbol, initialRecipient, initialSupply, maxSupply);
        vm.stopBroadcast();

        console2.log("GCC token:", address(token));
        console2.log("owner:", token.owner());
        console2.log("maxSupply:", token.maxSupply());
    }
}
