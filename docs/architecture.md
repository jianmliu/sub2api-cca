# GCT CCA Architecture

## Phase 1: Ethereum Sepolia

```text
Deployer
  -> deploys GCT ERC20 with EIP-3009 authorization transfers
  -> creates CCA auction using Uniswap CCA factory
  -> mints auction supply to auction contract
  -> calls auction.onTokensReceived()

Bidder
  -> bids with Sepolia ETH or Sepolia ERC20 test currency
  -> claims GCT after claim block

AI.GG backend
  -> observes or accepts GCT deposits
  -> can settle x402 GCT payments through transferWithAuthorization
  -> mirrors deposits into users.gct_balance
  -> consumes GCT by USD-cost / GCT price
```

## Open Decisions

- Raise currency address: Sepolia ETH initially, or Sepolia test USDC if we want stablecoin-like bids.
- Whether GCT should be mintable after launch or capped permanently.
- Whether bidder eligibility needs a validation hook.
- Whether backend price source should use CCA clearing price, Uniswap pool TWAP, or a manually pinned
  launch price during MVP.
