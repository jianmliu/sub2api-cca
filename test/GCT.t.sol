// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { GCT } from "../src/GCT.sol";

contract GCTTest is Test {
    GCT private token;

    function testOwnerCanMint() public {
        token = new GCT("Guaranteed Capacity Token", "GCT", address(this), 0);

        token.mint(address(0xBEEF), 100 ether);

        assertEq(token.balanceOf(address(0xBEEF)), 100 ether);
        assertEq(token.totalSupply(), 100 ether);
    }

    function testNonOwnerCannotMint() public {
        token = new GCT("Guaranteed Capacity Token", "GCT", address(this), 0);

        vm.prank(address(0xBEEF));
        vm.expectRevert(GCT.NotOwner.selector);
        token.mint(address(0xBEEF), 1 ether);
    }

    function testTransferWithAuthorization() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        address recipient = address(0xBEEF);
        token = new GCT("Guaranteed Capacity Token", "GCT", owner, 10 ether);

        bytes32 nonce = keccak256("nonce-1");
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _signTransfer(privateKey, owner, recipient, 2 ether, validAfter, validBefore, nonce);

        token.transferWithAuthorization(
            owner, recipient, 2 ether, validAfter, validBefore, nonce, v, r, s
        );

        assertEq(token.balanceOf(owner), 8 ether);
        assertEq(token.balanceOf(recipient), 2 ether);
        assertTrue(token.authorizationState(owner, nonce));
    }

    function testTransferWithAuthorizationAcceptsZeroOneV() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        address recipient = address(0xBEEF);
        token = new GCT("Guaranteed Capacity Token", "GCT", owner, 10 ether);

        bytes32 nonce = keccak256("nonce-zero-one-v");
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _signTransfer(privateKey, owner, recipient, 2 ether, validAfter, validBefore, nonce);

        token.transferWithAuthorization(
            owner, recipient, 2 ether, validAfter, validBefore, nonce, v - 27, r, s
        );

        assertEq(token.balanceOf(recipient), 2 ether);
    }

    function testTransferWithAuthorizationRejectsReplay() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        address recipient = address(0xBEEF);
        token = new GCT("Guaranteed Capacity Token", "GCT", owner, 10 ether);

        bytes32 nonce = keccak256("nonce-1");
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _signTransfer(privateKey, owner, recipient, 2 ether, validAfter, validBefore, nonce);

        token.transferWithAuthorization(
            owner, recipient, 2 ether, validAfter, validBefore, nonce, v, r, s
        );
        vm.expectRevert(GCT.AuthorizationAlreadyUsed.selector);
        token.transferWithAuthorization(
            owner, recipient, 2 ether, validAfter, validBefore, nonce, v, r, s
        );
    }

    function testReceiveWithAuthorizationRequiresPayeeCaller() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        address recipient = address(0xBEEF);
        token = new GCT("Guaranteed Capacity Token", "GCT", owner, 10 ether);

        bytes32 nonce = keccak256("receive-nonce");
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _signReceive(privateKey, owner, recipient, 2 ether, validAfter, validBefore, nonce);

        vm.expectRevert(GCT.CallerMustBePayee.selector);
        token.receiveWithAuthorization(
            owner, recipient, 2 ether, validAfter, validBefore, nonce, v, r, s
        );

        vm.prank(recipient);
        token.receiveWithAuthorization(
            owner, recipient, 2 ether, validAfter, validBefore, nonce, v, r, s
        );

        assertEq(token.balanceOf(owner), 8 ether);
        assertEq(token.balanceOf(recipient), 2 ether);
        assertTrue(token.authorizationState(owner, nonce));
    }

    function testCancelAuthorizationBlocksTransfer() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        address recipient = address(0xBEEF);
        token = new GCT("Guaranteed Capacity Token", "GCT", owner, 10 ether);

        bytes32 nonce = keccak256("cancel-nonce");
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 cancelV, bytes32 cancelR, bytes32 cancelS) = _signCancel(privateKey, owner, nonce);
        (uint8 transferV, bytes32 transferR, bytes32 transferS) =
            _signTransfer(privateKey, owner, recipient, 2 ether, validAfter, validBefore, nonce);

        token.cancelAuthorization(owner, nonce, cancelV, cancelR, cancelS);

        assertTrue(token.authorizationState(owner, nonce));
        vm.expectRevert(GCT.AuthorizationAlreadyUsed.selector);
        token.transferWithAuthorization(
            owner,
            recipient,
            2 ether,
            validAfter,
            validBefore,
            nonce,
            transferV,
            transferR,
            transferS
        );
    }

    function testTransferWithAuthorizationRejectsInvalidSignature() public {
        uint256 ownerPrivateKey = 0xA11CE;
        uint256 otherPrivateKey = 0xB0B;
        address owner = vm.addr(ownerPrivateKey);
        address recipient = address(0xBEEF);
        token = new GCT("Guaranteed Capacity Token", "GCT", owner, 10 ether);

        bytes32 nonce = keccak256("bad-signer");
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransfer(
            otherPrivateKey, owner, recipient, 2 ether, validAfter, validBefore, nonce
        );

        vm.expectRevert(GCT.InvalidSignature.selector);
        token.transferWithAuthorization(
            owner, recipient, 2 ether, validAfter, validBefore, nonce, v, r, s
        );
    }

    function _signTransfer(
        uint256 privateKey,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) private view returns (uint8 v, bytes32 r, bytes32 s) {
        return _signTransferLike(
            privateKey,
            token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce
        );
    }

    function _signReceive(
        uint256 privateKey,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) private view returns (uint8 v, bytes32 r, bytes32 s) {
        return _signTransferLike(
            privateKey,
            token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce
        );
    }

    function _signTransferLike(
        uint256 privateKey,
        bytes32 typeHash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) private view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(typeHash, from, to, value, validAfter, validBefore, nonce)
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(privateKey, digest);
    }

    function _signCancel(uint256 privateKey, address authorizer, bytes32 nonce)
        private
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash =
            keccak256(abi.encode(token.CANCEL_AUTHORIZATION_TYPEHASH(), authorizer, nonce));
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(privateKey, digest);
    }
}
