// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { SubscriptionPass } from "../src/SubscriptionPass.sol";

contract SubscriptionPassTest is Test {
    SubscriptionPass private pass;
    address private owner = address(0xA11CE);
    address private user = address(0xB0B);
    address private other = address(0xCAFE);

    function setUp() public {
        vm.prank(owner);
        pass = new SubscriptionPass("AI.GG Subscription Pass", "AIGG-SUB", owner);
    }

    function testMintCreatesOneTokenPerOwner() public {
        vm.prank(owner);
        uint256 tokenId = pass.mint(user, 1, 30 days);

        assertEq(tokenId, 1);
        assertEq(pass.ownerOf(tokenId), user);
        assertEq(pass.tokenOfOwner(user), tokenId);
        assertEq(pass.tierOf(tokenId), 1);
        assertGt(pass.expiresAt(tokenId), block.timestamp);
    }

    function testMintRejectsSecondTokenForSameOwner() public {
        vm.startPrank(owner);
        pass.mint(user, 1, 30 days);
        vm.expectRevert(
            abi.encodeWithSelector(SubscriptionPass.AlreadySubscribed.selector, user, 1)
        );
        pass.mint(user, 2, 30 days);
        vm.stopPrank();
    }

    function testTokenZeroIsNotUsed() public {
        assertEq(pass.tokenOfOwner(user), 0);
        vm.prank(owner);
        uint256 tokenId = pass.mint(user, 1, 1 days);
        assertGt(tokenId, 0);
    }

    function testRenewExtendsFromCurrentExpiration() public {
        vm.prank(owner);
        uint256 tokenId = pass.mint(user, 1, 30 days);
        uint64 firstExpiration = pass.expiresAt(tokenId);

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        pass.renewSubscription(tokenId, 7 days);

        assertEq(pass.expiresAt(tokenId), firstExpiration + uint64(7 days));
    }

    function testCancelBurnsAndClearsOwnerIndex() public {
        vm.prank(owner);
        uint256 tokenId = pass.mint(user, 1, 30 days);

        vm.prank(user);
        pass.cancelSubscription(tokenId);

        assertEq(pass.tokenOfOwner(user), 0);
        vm.expectRevert();
        pass.ownerOf(tokenId);
    }

    function testSoulboundTransferReverts() public {
        vm.prank(owner);
        uint256 tokenId = pass.mint(user, 1, 30 days);

        vm.prank(user);
        vm.expectRevert(SubscriptionPass.Soulbound.selector);
        pass.transferFrom(user, other, tokenId);
    }

    function testTierCanBeRaisedByOwner() public {
        vm.prank(owner);
        uint256 tokenId = pass.mint(user, 1, 30 days);

        vm.prank(owner);
        pass.setTier(tokenId, 3);

        assertEq(pass.tierOf(tokenId), 3);
    }
}
