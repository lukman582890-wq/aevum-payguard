# Aevum PayGuard — Scoped Agentic `tUSD8` Invoice & Confirmation-of-Payee Payments

Built for **Aevum Builder Challenge #1** on **QDay Aevum Testnet (Chain ID `44005`)**.

## Problem & Innovation

Businesses and AI agents paying invoices on-chain face two major operational risks:
1. **Unbounded Wallet Risk:** Giving an automated agent direct spending access to a treasury wallet risks draining funds on bugs or prompt injection.
2. **Wrong-Address Payouts:** Sending stablecoins (`tUSD8`) to an unverified merchant address is irreversible.

**Aevum PayGuard** solves both in a single, gas-efficient, zero-dependency Solidity `0.8.24` contract paired with a live QDay Aevum Testnet web dApp:
- **Confirmation of Payee Registry:** Merchants register their handle and `identityHash` on-chain (`registerPayee` / `setPayeeActive`).
- **Least-Privilege Agent Sessions:** Payers authorize an agent with strict `maxBudget`, `perTxCap`, `expiresAt`, optional `requireVerifiedPayee`, and instant `revokeSession`.
- **Idempotent `tUSD8` Invoice Settlement:** Verifiable invoices (`createInvoice`, `cancelInvoice`, `payInvoiceViaSession`, `payInvoiceDirect`) with custom reentrancy guard, SafeERC20-style transfer validation, and full on-chain audit events.

## Architecture

```
Payer Treasury ──(createSession: maxBudget, perTxCap, expiry, verifiedPayeeOnly)──▶ AevumPayGuard.sol
Merchant       ──(registerPayee + createInvoice in tUSD8)─────────────────────────▶ AevumPayGuard.sol
AI Agent       ──(payInvoiceViaSession)──▶ Checks: Active + Expiry + CoP + Caps ──▶ tUSD8.transferFrom()
```

## QDay Aevum Testnet Configuration

| Parameter | Value |
|---|---|
| **Network** | QDay Aevum Testnet |
| **Chain ID** | `44005` (`0xABE5`) |
| **RPC URL** | `https://rpc-test.qday.info` |
| **Block Explorer** | `https://explorer-test.qday.info/` |
| **Native Gas Token** | `tQDAY` (18 decimals) |
| **Test Stablecoin (`tUSD8`)** | `0x456569838f1d43009A91ebA4263147Afd7233483` (6 decimals) |

## Quick Start

### 1. Verify Live Aevum Testnet RPC & `tUSD8` Contract

```bash
python scripts/rpc_verify.py
```

### 2. Compile & Verify Solidity Contracts (`solc 0.8.24`)

```bash
npm install
npm run compile
```

### 3. Launch the Interactive Web dApp (or via Docker)

```bash
npm run serve
# Open http://localhost:8088
```

Or with Docker:

```bash
docker build -t aevum-payguard .
docker run -p 8088:8088 aevum-payguard
```

### 4. Deploy & Verify on QDay Aevum Testnet (Foundry)

```bash
forge create contracts/AevumPayGuard.sol:AevumPayGuard \
  --rpc-url https://rpc-test.qday.info \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --constructor-args 0x456569838f1d43009A91ebA4263147Afd7233483

forge verify-contract --chain-id 44005 --verifier blockscout \
  --verifier-url https://explorer-test.qday.info/api \
  <DEPLOYED_ADDRESS> contracts/AevumPayGuard.sol:AevumPayGuard
```

## Demo Video

- 2-minute 1080p narrated walkthrough: [`demo/aevum_payguard_demo.mp4`](demo/aevum_payguard_demo.mp4)
