#!/usr/bin/env python3
"""
Idempotent Circle Programmable Wallets setup for AI.GG agent-endpoint smoke
tests.

First run:
  - Generates a 32-byte entity secret.
  - Registers it via POST /v1/w3s/config/entity/entitySecret.
  - Creates a Wallet Set + one BASE-SEPOLIA developer-controlled wallet.
  - Writes the secret hex, wallet set ID, and wallet ID to
    aigg-cca/.env.circle (gitignored via the .env.* glob).
  - Writes the Circle-issued recovery file to aigg-cca/circle-recovery.dat
    (gitignored explicitly).

Subsequent runs (when .env.circle already has CIRCLE_ENTITY_SECRET_HEX +
CIRCLE_WALLET_ID set):
  - Skips registration (Circle rejects duplicate registers anyway).
  - Skips wallet creation.
  - Confirms the saved wallet is still LIVE by fetching it.
  - Prints the ready-to-curl /auth/agent/circle command.

Usage:
  cd aigg-cca
  source .env.circle 2>/dev/null  # OK if missing on first run
  CIRCLE_API_KEY=$CIRCLE_API_KEY python3 scripts/circle_setup.py

Requirements: pycryptodome (pip install --user pycryptodome).
"""

import base64
import os
import secrets
import sys
import uuid
from pathlib import Path

import requests
from Crypto.Cipher import PKCS1_OAEP
from Crypto.Hash import SHA256
from Crypto.PublicKey import RSA

REPO_ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = REPO_ROOT / ".env.circle"
RECOVERY_FILE = REPO_ROOT / "circle-recovery.dat"

API_KEY = os.environ.get("CIRCLE_API_KEY", "").strip()
if not API_KEY:
    print("ERROR: set CIRCLE_API_KEY env var (source .env.circle or export it)",
          file=sys.stderr)
    sys.exit(1)

BASE = "https://api.circle.com/v1/w3s"
HDRS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}


def fetch_public_key() -> str:
    r = requests.get(f"{BASE}/config/entity/publicKey", headers=HDRS, timeout=15)
    r.raise_for_status()
    return r.json()["data"]["publicKey"]


def encrypt(secret_bytes: bytes, public_key_pem: str) -> str:
    pub = RSA.import_key(public_key_pem)
    cipher = PKCS1_OAEP.new(key=pub, hashAlgo=SHA256)
    return base64.b64encode(cipher.encrypt(secret_bytes)).decode()


def write_env(secret_hex: str, wallet_set_id: str, wallet_id: str, address: str) -> None:
    # Preserve the existing CIRCLE_API_KEY line by reading any current content
    # and replacing only the keys we manage.
    existing = {}
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            existing[k.strip()] = v.strip()
    existing["CIRCLE_API_KEY"] = API_KEY
    existing["CIRCLE_ENTITY_SECRET_HEX"] = secret_hex
    existing["CIRCLE_WALLET_SET_ID"] = wallet_set_id
    existing["CIRCLE_WALLET_ID"] = wallet_id
    existing["CIRCLE_WALLET_ADDRESS"] = address

    lines = [
        "# AI.GG Circle Programmable Wallets test credentials (Base Sepolia)",
        "# Managed by scripts/circle_setup.py. Gitignored via .env.* glob.",
        "",
    ]
    for k in (
        "CIRCLE_API_KEY",
        "CIRCLE_ENTITY_SECRET_HEX",
        "CIRCLE_WALLET_SET_ID",
        "CIRCLE_WALLET_ID",
        "CIRCLE_WALLET_ADDRESS",
    ):
        if k in existing:
            lines.append(f"{k}={existing[k]}")
    ENV_FILE.write_text("\n".join(lines) + "\n")
    ENV_FILE.chmod(0o600)


def main() -> None:
    existing_secret_hex = os.environ.get("CIRCLE_ENTITY_SECRET_HEX", "").strip()
    existing_wallet_id = os.environ.get("CIRCLE_WALLET_ID", "").strip()
    existing_wallet_set_id = os.environ.get("CIRCLE_WALLET_SET_ID", "").strip()
    reused = bool(existing_secret_hex and existing_wallet_id)

    if reused:
        print("== reusing saved Circle setup ==")
        r = requests.get(f"{BASE}/wallets/{existing_wallet_id}", headers=HDRS, timeout=15)
        if r.status_code >= 400:
            print(f"  saved wallet {existing_wallet_id} no longer accessible "
                  f"({r.status_code}); delete .env.circle to re-run setup",
                  file=sys.stderr)
            sys.exit(2)
        w = r.json()["data"]["wallet"]
        print(f"  wallet_id:    {w['id']}")
        print(f"  blockchain:   {w['blockchain']}")
        print(f"  address:      {w.get('address', '(provisioning)')}")
        print(f"  state:        {w['state']}")
        print()
        _print_curl(w["id"])
        return

    print("== 1. fetch Circle entity public key ==")
    public_key_pem = fetch_public_key()

    print("== 2. generate 32-byte entity secret ==")
    entity_secret = secrets.token_bytes(32)
    secret_hex = entity_secret.hex()

    print("== 3. register entity secret ==")
    r = requests.post(
        f"{BASE}/config/entity/entitySecret",
        headers=HDRS,
        json={"entitySecretCiphertext": encrypt(entity_secret, public_key_pem)},
        timeout=15,
    )
    if r.status_code >= 400:
        print(f"  registration failed: {r.status_code} {r.text}", file=sys.stderr)
        sys.exit(3)
    recovery = r.json().get("data", {}).get("recoveryFile", "")
    if recovery:
        RECOVERY_FILE.write_text(recovery)
        RECOVERY_FILE.chmod(0o600)
        print(f"  recovery file: {RECOVERY_FILE}")

    print("== 4. create wallet set ==")
    r = requests.post(
        f"{BASE}/developer/walletSets",
        headers=HDRS,
        json={
            "idempotencyKey": str(uuid.uuid4()),
            "name": "aigg-agent-sepolia",
            "entitySecretCiphertext": encrypt(entity_secret, public_key_pem),
        },
        timeout=15,
    )
    if r.status_code >= 400:
        print(f"  wallet set creation failed: {r.status_code} {r.text}", file=sys.stderr)
        sys.exit(4)
    wallet_set_id = r.json()["data"]["walletSet"]["id"]

    print("== 5. create Base Sepolia wallet ==")
    r = requests.post(
        f"{BASE}/developer/wallets",
        headers=HDRS,
        json={
            "idempotencyKey": str(uuid.uuid4()),
            "walletSetId": wallet_set_id,
            "blockchains": ["BASE-SEPOLIA"],
            "count": 1,
            "accountType": "EOA",
            "entitySecretCiphertext": encrypt(entity_secret, public_key_pem),
        },
        timeout=30,
    )
    if r.status_code >= 400:
        print(f"  wallet creation failed: {r.status_code} {r.text}", file=sys.stderr)
        sys.exit(5)
    wallets = r.json()["data"]["wallets"]
    if not wallets:
        print("  no wallets returned", file=sys.stderr)
        sys.exit(6)
    w = wallets[0]

    print("== 6. persist to .env.circle ==")
    write_env(secret_hex, wallet_set_id, w["id"], w.get("address", ""))
    print(f"  wrote: {ENV_FILE}")

    print()
    print("== READY ==")
    print(f"  wallet_id:    {w['id']}")
    print(f"  blockchain:   {w['blockchain']}")
    print(f"  address:      {w.get('address', '(provisioning)')}")
    print(f"  state:        {w['state']}")
    print()
    _print_curl(w["id"])
    _ = existing_wallet_set_id  # kept for future "wallet set already exists" branch


def _print_curl(wallet_id: str) -> None:
    print("  Next: smoke-test the AI.GG agent endpoint:")
    print()
    print(
        f"  curl -X POST https://www.ai.gg/api/v1/auth/agent/circle "
        f"\\\n    -H 'Content-Type: application/json' "
        f"\\\n    -d '{{\"circle_api_key\":\"'\"$CIRCLE_API_KEY\"'\",\"circle_wallet_id\":\"{wallet_id}\"}}'"
    )


if __name__ == "__main__":
    main()
