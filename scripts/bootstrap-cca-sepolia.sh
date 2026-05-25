#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy .env.example to .env and fill PRIVATE_KEY first." >&2
  exit 1
fi

cd "$ROOT_DIR"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ -z "${PRIVATE_KEY:-}" || "$PRIVATE_KEY" =~ ^0x0+$ ]]; then
  echo "PRIVATE_KEY is not configured in $ENV_FILE." >&2
  exit 1
fi

if [[ -z "${RPC_URL:-}" || -z "${CHAIN_ID:-}" ]]; then
  echo "RPC_URL and CHAIN_ID must be configured in $ENV_FILE." >&2
  exit 1
fi

if [[ "${CHAIN_ID}" != "11155111" ]]; then
  echo "Refusing to bootstrap on CHAIN_ID=$CHAIN_ID; expected Ethereum Sepolia 11155111." >&2
  exit 1
fi

set_env_value() {
  local key="$1"
  local value="$2"
  local escaped
  escaped="$(printf '%s' "$value" | sed 's/[\/&]/\\&/g')"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i.bak "s/^${key}=.*/${key}=${escaped}/" "$ENV_FILE"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

extract_address() {
  local label="$1"
  local file="$2"
  awk -v label="$label" '
    index($0, label) {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^0x[0-9a-fA-F]{40}$/) {
          print $i
          exit
        }
      }
    }
  ' "$file"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "Deploying GCT ERC20 on Sepolia..."
forge script script/DeployGCT.s.sol:DeployGCT \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --chain-id "$CHAIN_ID" \
  --broadcast 2>&1 | tee "$tmpdir/deploy-gct.log"
gct_token="$(extract_address "GCT token:" "$tmpdir/deploy-gct.log")"
if [[ -z "$gct_token" ]]; then
  echo "Could not extract GCT token address from deploy-gct output." >&2
  exit 1
fi
set_env_value "GCT_TOKEN" "$gct_token"
export GCT_TOKEN="$gct_token"
echo "GCT_TOKEN=$gct_token"

echo "Deploying CCA distribution for GCT..."
forge script script/DeployGCTCCA.s.sol:DeployGCTCCA \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --chain-id "$CHAIN_ID" \
  --broadcast 2>&1 | tee "$tmpdir/deploy-cca.log"
cca_auction="$(extract_address "CCA auction:" "$tmpdir/deploy-cca.log")"
if [[ -z "$cca_auction" ]]; then
  echo "Could not extract CCA auction address from deploy-cca output." >&2
  exit 1
fi
set_env_value "CCA_AUCTION" "$cca_auction"
export CCA_AUCTION="$cca_auction"
echo "CCA_AUCTION=$cca_auction"

echo
echo "Bootstrap complete. Use this GCT address for sub2api-listings:"
echo "X402_GCT_ASSET=$gct_token"
echo "GCT_TOKEN=$gct_token"
echo "CCA_AUCTION=$cca_auction"
