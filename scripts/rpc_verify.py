"""Live JSON-RPC verification script for QDay Aevum Testnet (Chain ID 44005) & tUSD8."""

from __future__ import annotations

import json
import sys
import requests

RPC_URL = "https://rpc-test.qday.info"
EXPECTED_CHAIN_ID = 44005
TUSD8_ADDRESS = "0x456569838f1d43009A91ebA4263147Afd7233483"
FAUCET_ADDRESS = "0x33d19Bde2e1798c13808f17BfBa1780b28e4bACC"


def rpc_call(method: str, params: list) -> dict:
    resp = requests.post(
        RPC_URL,
        json={"jsonrpc": "2.0", "method": method, "params": params, "id": 1},
        timeout=20,
    )
    resp.raise_for_status()
    return resp.json()


def decode_abi_string(hex_data: str) -> str:
    raw = bytes.fromhex(hex_data.removeprefix("0x"))
    if len(raw) < 64:
        return ""
    length = int.from_bytes(raw[32:64], "big")
    return raw[64 : 64 + length].decode("utf-8", errors="ignore")


def main() -> int:
    chain_id = int(rpc_call("eth_chainId", [])["result"], 16)
    block_num = int(rpc_call("eth_blockNumber", [])["result"], 16)
    gas_price = int(rpc_call("eth_gasPrice", [])["result"], 16)

    sym_hex = rpc_call("eth_call", [{"to": TUSD8_ADDRESS, "data": "0x95d89b41"}, "latest"])["result"]
    dec_hex = rpc_call("eth_call", [{"to": TUSD8_ADDRESS, "data": "0x313ce567"}, "latest"])["result"]
    sup_hex = rpc_call("eth_call", [{"to": TUSD8_ADDRESS, "data": "0x18160ddd"}, "latest"])["result"]
    faucet_code = rpc_call("eth_getCode", [FAUCET_ADDRESS, "latest"])["result"]

    symbol = decode_abi_string(sym_hex)
    decimals = int(dec_hex, 16)
    total_supply = int(sup_hex, 16) / (10**decimals)

    report = {
        "rpc_url": RPC_URL,
        "chain_id": chain_id,
        "chain_id_match": chain_id == EXPECTED_CHAIN_ID,
        "latest_block": block_num,
        "gas_price_wei": gas_price,
        "tusd8": {
            "address": TUSD8_ADDRESS,
            "symbol": symbol,
            "decimals": decimals,
            "total_supply_formatted": round(total_supply, 2),
        },
        "faucet_contract_live": len(faucet_code) > 4,
    }
    print(json.dumps(report, indent=2))
    assert chain_id == EXPECTED_CHAIN_ID, f"Expected chain_id {EXPECTED_CHAIN_ID}, got {chain_id}"
    assert decimals == 6, f"Expected 6 decimals for tUSD8, got {decimals}"
    assert len(faucet_code) > 4, "Faucet contract bytecode missing"
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
