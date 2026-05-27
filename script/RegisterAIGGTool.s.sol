// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { IToolRegistry } from "../src/interfaces/IToolRegistry.sol";

contract RegisterAIGGTool is Script {
    uint256 private constant BASE_CHAIN_ID = 8453;

    error WrongChain(uint256 chainId);

    function run() external returns (uint256 toolId) {
        _requireBaseChain();

        IToolRegistry registry = IToolRegistry(
            vm.envOr("ERC8257_TOOL_REGISTRY", address(0x265BB2DBFC0A8165C9A1941Eb1372F349baD2cf1))
        );
        address predicate = vm.envOr(
            "ERC8257_SUBSCRIPTION_PREDICATE", address(0xCBe0cd9B1d99d95Baa9c58f2767246C52e461f25)
        );
        string memory metadataURI = vm.envString("AIGG_TOOL_METADATA_URI");
        bytes32 manifestHash = vm.envBytes32("AIGG_TOOL_MANIFEST_HASH");

        vm.startBroadcast();
        toolId = registry.registerTool(metadataURI, manifestHash, predicate);
        vm.stopBroadcast();

        console2.log("tool id:", toolId);
        console2.log("registry:", address(registry));
        console2.log("predicate:", predicate);
        console2.log("metadata URI:", metadataURI);
    }

    function _requireBaseChain() private view {
        bool allowNonBase = vm.envOr("ALLOW_NON_BASE_ERC8257", false);
        if (block.chainid != BASE_CHAIN_ID && !allowNonBase) revert WrongChain(block.chainid);
    }
}
