// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct AuctionParameters {
    address currency;
    address tokensRecipient;
    address fundsRecipient;
    uint64 startBlock;
    uint64 endBlock;
    uint64 claimBlock;
    uint256 tickSpacing;
    address validationHook;
    uint256 floorPrice;
    uint128 requiredCurrencyRaised;
    bytes auctionStepsData;
}

interface IContinuousClearingAuction {
    event BidSubmitted(uint256 indexed id, address indexed owner, uint256 price, uint128 amount);
    event BidExited(
        uint256 indexed bidId, address indexed owner, uint256 tokensFilled, uint256 currencyRefunded
    );
    event TokensClaimed(uint256 indexed bidId, address indexed owner, uint256 tokensFilled);

    function submitBid(uint256 maxPrice, uint128 amount, address owner, bytes calldata hookData)
        external
        payable
        returns (uint256 bidId);

    function exitBid(uint256 bidId) external;
    function claimTokens(uint256 bidId) external;
    function clearingPrice() external view returns (uint256);
    function currencyRaised() external view returns (uint256);
    function token() external view returns (address);
    function currency() external view returns (address);
    function startBlock() external view returns (uint64);
    function endBlock() external view returns (uint64);
    function claimBlock() external view returns (uint64);
}
