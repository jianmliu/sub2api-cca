// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISubscriptionPredicate {
    struct ToolGatingConfig {
        address collection;
        uint8 minTier;
    }

    function configureToolGating(uint256 toolId, address collection, uint8 minTier) external;

    function getToolGatingConfig(uint256 toolId) external view returns (ToolGatingConfig memory);

    function getSubscriptionStatus(uint256 toolId, address account)
        external
        view
        returns (bool hasNft, uint8 tier, uint8 requiredTier, uint64 expiration, bool active);
}
