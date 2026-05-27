# AI.GG ERC-8257 Base Deployment

Canonical Base contracts:

- ToolRegistry: `0x265BB2DBFC0A8165C9A1941Eb1372F349baD2cf1`
- SubscriptionPredicate: `0xCBe0cd9B1d99d95Baa9c58f2767246C52e461f25`

Deploy AI.GG SubscriptionPass:

```bash
cd /Volumes/T7-Data/sub2api3/AIGG/aigg-cca
SUBSCRIPTION_PASS_OWNER="$BASE_DEPLOYER_ADDRESS" \
forge script script/DeploySubscriptionPass.s.sol:DeploySubscriptionPass \
  --rpc-url "$BASE_RPC_URL" \
  --private-key "$BASE_DEPLOYER_PRIVATE_KEY" \
  --broadcast
```

Validate manifest and compute hash:

```bash
cd /Volumes/T7-Data/sub2api3/AIGG/aigg-src/frontend
npx @opensea/tool-sdk validate public/.well-known/ai-tool/aigg-gateway.json
npx @opensea/tool-sdk hash public/.well-known/ai-tool/aigg-gateway.json
```

Register AI.GG tool:

```bash
cd /Volumes/T7-Data/sub2api3/AIGG/aigg-cca
AIGG_TOOL_METADATA_URI="https://www.ai.gg/.well-known/ai-tool/aigg-gateway.json" \
AIGG_TOOL_MANIFEST_HASH="$AIGG_TOOL_MANIFEST_HASH" \
forge script script/RegisterAIGGTool.s.sol:RegisterAIGGTool \
  --rpc-url "$BASE_RPC_URL" \
  --private-key "$BASE_DEPLOYER_PRIVATE_KEY" \
  --broadcast
```

Configure subscription predicate:

```bash
cd /Volumes/T7-Data/sub2api3/AIGG/aigg-cca
AIGG_TOOL_ID="$AIGG_TOOL_ID" \
AIGG_SUBSCRIPTION_PASS="$AIGG_SUBSCRIPTION_PASS" \
AIGG_MIN_SUBSCRIPTION_TIER=1 \
forge script script/ConfigureAIGGSubscriptionPredicate.s.sol:ConfigureAIGGSubscriptionPredicate \
  --rpc-url "$BASE_RPC_URL" \
  --private-key "$BASE_DEPLOYER_PRIVATE_KEY" \
  --broadcast
```

SDK verification:

```bash
cd /Volumes/T7-Data/sub2api3/AIGG/aigg-src/frontend
npx @opensea/tool-sdk inspect --tool-id "$AIGG_TOOL_ID" --network base
npx @opensea/tool-sdk inspect --tool-id "$AIGG_TOOL_ID" --network base --check-access "$USER_ADDRESS"
```

The generic `tool-sdk set-collections` command configures the SDK's ERC-721 collection
predicate. AI.GG subscription access uses the SubscriptionPredicate above, so predicate
configuration should be done with `ConfigureAIGGSubscriptionPredicate`.

Set `ALLOW_NON_BASE_ERC8257=true` only for local forks or explicit non-Base dry runs. The
deployment and registry scripts otherwise require `block.chainid == 8453`.
