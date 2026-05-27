// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IToolRegistry {
    struct ToolConfig {
        address creator;
        string metadataURI;
        bytes32 manifestHash;
        address accessPredicate;
        bool active;
    }

    function registerTool(
        string calldata metadataURI,
        bytes32 manifestHash,
        address accessPredicate
    ) external returns (uint256 toolId);

    function updateToolMetadata(uint256 toolId, string calldata newURI, bytes32 newHash) external;

    function getToolConfig(uint256 toolId) external view returns (ToolConfig memory);

    function tryHasAccess(uint256 toolId, address account, bytes calldata data)
        external
        view
        returns (bool ok, bool granted);
}
