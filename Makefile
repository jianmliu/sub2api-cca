-include .env
export

.PHONY: build test bootstrap-cca deploy-gct deploy-cca bid-cca claim-cca deposit-gct

build:
	forge build

test:
	forge test

bootstrap-cca:
	scripts/bootstrap-cca-sepolia.sh

deploy-gct:
	forge script script/DeployGCT.s.sol:DeployGCT \
		--rpc-url "$$RPC_URL" \
		--private-key "$$PRIVATE_KEY" \
		--chain-id "$$CHAIN_ID" \
		--broadcast

deploy-cca:
	forge script script/DeployGCTCCA.s.sol:DeployGCTCCA \
		--rpc-url "$$RPC_URL" \
		--private-key "$$PRIVATE_KEY" \
		--chain-id "$$CHAIN_ID" \
		--broadcast

bid-cca:
	forge script script/BidGCTCCA.s.sol:BidGCTCCA \
		--rpc-url "$$RPC_URL" \
		--private-key "$$PRIVATE_KEY" \
		--chain-id "$$CHAIN_ID" \
		--broadcast

claim-cca:
	forge script script/ExitClaimGCTCCA.s.sol:ExitClaimGCTCCA \
		--rpc-url "$$RPC_URL" \
		--private-key "$$PRIVATE_KEY" \
		--chain-id "$$CHAIN_ID" \
		--broadcast

deposit-gct:
	forge script script/TransferGCTToPlatform.s.sol:TransferGCTToPlatform \
		--rpc-url "$$RPC_URL" \
		--private-key "$$PRIVATE_KEY" \
		--chain-id "$$CHAIN_ID" \
		--broadcast
