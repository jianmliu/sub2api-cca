// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IContinuousClearingAuctionFactory {
    function initializeDistribution(
        address token,
        uint256 tokenAmount,
        bytes calldata auctionParameters,
        bytes32 salt
    ) external returns (address auction);
}
