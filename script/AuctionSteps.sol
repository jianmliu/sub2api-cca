// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library AuctionSteps {
    uint64 internal constant TOTAL_MPS = 10_000_000;

    function forDuration(uint64 blockSpan) internal pure returns (bytes memory) {
        require(blockSpan > 0, "CCA duration is zero");

        uint64 baseMps = TOTAL_MPS / blockSpan;
        uint64 remainder = TOTAL_MPS - (baseMps * blockSpan);

        if (remainder == 0 || blockSpan == 1) {
            return abi.encodePacked(_step(baseMps + remainder, blockSpan));
        }

        return abi.encodePacked(_step(baseMps, blockSpan - 1), _step(baseMps + remainder, 1));
    }

    function _step(uint64 mpsPerBlock, uint64 blockSpan) private pure returns (bytes8) {
        require(mpsPerBlock <= type(uint24).max, "CCA mps too large");
        require(blockSpan <= type(uint40).max, "CCA block span too large");

        return bytes8((uint64(mpsPerBlock) << 40) | uint64(blockSpan));
    }
}
