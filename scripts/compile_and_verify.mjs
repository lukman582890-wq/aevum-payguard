import fs from "node:fs";
import path from "node:path";
import solc from "solc";

const root = process.cwd();
const sources = {
  "AevumPayGuard.sol": {
    content: fs.readFileSync(path.join(root, "contracts", "AevumPayGuard.sol"), "utf8"),
  },
  "MockTUSD8.sol": {
    content: fs.readFileSync(path.join(root, "contracts", "MockTUSD8.sol"), "utf8"),
  },
};

const input = {
  language: "Solidity",
  sources,
  settings: {
    optimizer: { enabled: true, runs: 200 },
    outputSelection: {
      "*": {
        "*": ["abi", "evm.bytecode.object", "evm.deployedBytecode.object"],
      },
    },
  },
};

const output = JSON.parse(solc.compile(JSON.stringify(input)));
const errors = (output.errors || []).filter((e) => e.severity === "error");
if (errors.length > 0) {
  console.error("Solidity compilation errors:", errors);
  process.exit(1);
}

const outDir = path.join(root, "artifacts");
fs.mkdirSync(outDir, { recursive: true });

for (const [file, contracts] of Object.entries(output.contracts)) {
  for (const [name, artifact] of Object.entries(contracts)) {
    const bytecode = artifact.evm.bytecode.object;
    const deployedBytes = artifact.evm.deployedBytecode.object.length / 2;
    const fnCount = artifact.abi.filter((x) => x.type === "function").length;
    const evCount = artifact.abi.filter((x) => x.type === "event").length;
    fs.writeFileSync(
      path.join(outDir, `${name}.json`),
      JSON.stringify({ contractName: name, abi: artifact.abi, bytecode: `0x${bytecode}` }, null, 2)
    );
    console.log(`[OK] ${file}:${name} | functions=${fnCount} events=${evCount} deployedBytes=${deployedBytes}`);
    if (deployedBytes > 24576) {
      throw new Error(`${name} exceeds EIP-170 24KB contract size limit`);
    }
  }
}
console.log("ALL CONTRACTS COMPILED & VERIFIED CLEANLY!");
