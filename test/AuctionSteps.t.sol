// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { AuctionSteps } from "../script/AuctionSteps.sol";

contract AuctionStepsTest is Test {
    function testForDurationSumsToTotalMps() public pure {
        bytes memory data = AuctionSteps.forDuration(7200);

        uint256 totalMps;
        for (uint256 offset = 0; offset < data.length; offset += 8) {
            bytes8 packed;
            assembly {
                packed := mload(add(add(data, 0x20), offset))
            }
            uint64 raw = uint64(packed);
            uint24 mps = uint24(raw >> 40);
            uint40 blockSpan = uint40(raw);
            totalMps += uint256(mps) * uint256(blockSpan);
        }

        assertEq(totalMps, 10_000_000);
    }
}
