// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { IContinuousClearingAuction } from "../src/interfaces/IContinuousClearingAuction.sol";

contract BidGCTCCA is Script {
    function run() external returns (uint256 bidId) {
        IContinuousClearingAuction auction =
            IContinuousClearingAuction(vm.envAddress("CCA_AUCTION"));
        uint256 maxPrice = vm.envUint("CCA_BID_MAX_PRICE_Q96");
        uint128 amount = uint128(vm.envUint("CCA_BID_AMOUNT"));
        address owner = vm.envOr("CCA_BID_OWNER", msg.sender);
        bytes memory hookData = vm.envOr("CCA_BID_HOOK_DATA", bytes(""));

        vm.startBroadcast();
        if (auction.currency() == address(0)) {
            bidId = auction.submitBid{ value: amount }(maxPrice, amount, owner, hookData);
        } else {
            bidId = auction.submitBid(maxPrice, amount, owner, hookData);
        }
        vm.stopBroadcast();

        console2.log("CCA auction:", address(auction));
        console2.log("bidId:", bidId);
        console2.log("owner:", owner);
        console2.log("amount:", amount);
        console2.log("maxPriceQ96:", maxPrice);
    }
}
