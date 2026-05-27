// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

interface IERC5643 {
    event SubscriptionUpdate(uint256 indexed tokenId, uint64 expiration);

    function renewSubscription(uint256 tokenId, uint64 duration) external payable;
    function cancelSubscription(uint256 tokenId) external payable;
    function expiresAt(uint256 tokenId) external view returns (uint64);
    function isRenewable(uint256 tokenId) external view returns (bool);
}

contract SubscriptionPass is ERC721, Ownable, IERC5643 {
    uint256 private nextTokenId = 1;

    mapping(address account => uint256 tokenId) private ownedToken;
    mapping(uint256 tokenId => uint64 timestamp) private expiration;
    mapping(uint256 tokenId => uint8 level) private tier;

    error Soulbound();
    error AlreadySubscribed(address account, uint256 existingTokenId);
    error InvalidTier();
    error InvalidDuration();
    error NonexistentToken(uint256 tokenId);
    error NotTokenOwnerOrAdmin(uint256 tokenId, address caller);
    error RefundFailed(address recipient, uint256 amount);

    constructor(string memory name_, string memory symbol_, address initialOwner)
        ERC721(name_, symbol_)
        Ownable(initialOwner)
    { }

    function mint(address to, uint8 tier_, uint64 duration)
        external
        onlyOwner
        returns (uint256 tokenId)
    {
        if (tier_ == 0) revert InvalidTier();
        if (duration == 0) revert InvalidDuration();
        uint256 existing = ownedToken[to];
        if (existing != 0) revert AlreadySubscribed(to, existing);

        tokenId = nextTokenId++;
        tier[tokenId] = tier_;
        uint64 newExpiration = uint64(block.timestamp) + duration;
        expiration[tokenId] = newExpiration;
        emit SubscriptionUpdate(tokenId, newExpiration);
        _safeMint(to, tokenId);
    }

    function tokenOfOwner(address account) external view returns (uint256) {
        return ownedToken[account];
    }

    function tierOf(uint256 tokenId) external view returns (uint8) {
        _requireMinted(tokenId);
        return tier[tokenId];
    }

    function expiresAt(uint256 tokenId) external view returns (uint64) {
        _requireMinted(tokenId);
        return expiration[tokenId];
    }

    function isRenewable(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function setTier(uint256 tokenId, uint8 newTier) external onlyOwner {
        if (newTier == 0) revert InvalidTier();
        _requireMinted(tokenId);
        tier[tokenId] = newTier;
    }

    function renewSubscription(uint256 tokenId, uint64 duration) external payable onlyOwner {
        if (duration == 0) revert InvalidDuration();
        _requireMinted(tokenId);
        uint64 current = expiration[tokenId];
        uint64 base = current > block.timestamp ? current : uint64(block.timestamp);
        uint64 newExpiration = base + duration;
        expiration[tokenId] = newExpiration;
        emit SubscriptionUpdate(tokenId, newExpiration);
        _refundIfAny();
    }

    function cancelSubscription(uint256 tokenId) external payable {
        address tokenOwner = _ownerOf(tokenId);
        if (tokenOwner == address(0)) revert NonexistentToken(tokenId);
        if (msg.sender != tokenOwner && msg.sender != owner()) {
            revert NotTokenOwnerOrAdmin(tokenId, msg.sender);
        }
        _burn(tokenId);
        emit SubscriptionUpdate(tokenId, 0);
        _refundIfAny();
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address from)
    {
        from = super._update(to, tokenId, auth);
        if (from != address(0) && to != address(0)) revert Soulbound();
        if (from != address(0)) {
            delete ownedToken[from];
            delete expiration[tokenId];
            delete tier[tokenId];
        }
        if (to != address(0)) {
            ownedToken[to] = tokenId;
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC5643).interfaceId || super.supportsInterface(interfaceId);
    }

    function _requireMinted(uint256 tokenId) private view {
        if (_ownerOf(tokenId) == address(0)) revert NonexistentToken(tokenId);
    }

    function _refundIfAny() private {
        uint256 value = msg.value;
        if (value == 0) return;
        (bool ok,) = msg.sender.call{ value: value }("");
        if (!ok) revert RefundFailed(msg.sender, value);
    }
}
