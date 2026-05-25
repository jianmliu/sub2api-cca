// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { GCT } from "../src/GCT.sol";

contract GCTTest is Test {
    function testOwnerCanMint() public {
        GCT token = new GCT("Guaranteed Capacity Token", "GCT", address(this), 0);

        token.mint(address(0xBEEF), 100 ether);

        assertEq(token.balanceOf(address(0xBEEF)), 100 ether);
        assertEq(token.totalSupply(), 100 ether);
    }

    function testNonOwnerCannotMint() public {
        GCT token = new GCT("Guaranteed Capacity Token", "GCT", address(this), 0);

        vm.prank(address(0xBEEF));
        vm.expectRevert(GCT.NotOwner.selector);
        token.mint(address(0xBEEF), 1 ether);
    }

    function testTransferWithAuthorization() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        address recipient = address(0xBEEF);
        GCT token = new GCT("Guaranteed Capacity Token", "GCT", owner, 10 ether);

        bytes32 nonce = keccak256("nonce-1");
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 typeHash = token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH();
        bytes32 structHash = keccak256(
            abi.encode(typeHash, owner, recipient, 2 ether, validAfter, validBefore, nonce)
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        token.transferWithAuthorization(
            owner, recipient, 2 ether, validAfter, validBefore, nonce, v, r, s
        );

        assertEq(token.balanceOf(owner), 8 ether);
        assertEq(token.balanceOf(recipient), 2 ether);
        assertTrue(token.authorizationState(owner, nonce));
    }

    function testTransferWithAuthorizationRejectsReplay() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        address recipient = address(0xBEEF);
        GCT token = new GCT("Guaranteed Capacity Token", "GCT", owner, 10 ether);

        bytes32 nonce = keccak256("nonce-1");
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                owner,
                recipient,
                2 ether,
                validAfter,
                validBefore,
                nonce
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        token.transferWithAuthorization(
            owner, recipient, 2 ether, validAfter, validBefore, nonce, v, r, s
        );
        vm.expectRevert(GCT.AuthorizationAlreadyUsed.selector);
        token.transferWithAuthorization(
            owner, recipient, 2 ether, validAfter, validBefore, nonce, v, r, s
        );
    }
}
