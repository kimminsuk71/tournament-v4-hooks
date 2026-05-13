#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { AbiCoder, concat, dataSlice, getCreate2Address, keccak256, toBeHex } from "ethers";

const flags = 0x0040n | 0x0004n;
const mask = (1n << 14n) - 1n;

function arg(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((item) => item.startsWith(prefix));
  if (found) return found.slice(prefix.length);
  const env = process.env[name.toUpperCase().replaceAll("-", "_")];
  return env ?? fallback;
}

const artifactPath = arg("artifact", "out/TournamentHook.sol/TournamentHook.json");
const deployer = arg("deployer");
const manager = arg("manager");
const vault = arg("vault");
const owner = arg("owner");
const feeBips = BigInt(arg("fee-bips", "100"));
const max = BigInt(arg("max", "1000000"));

if (!deployer || !manager || !vault || !owner) {
  console.error("Usage: mine-hook-salt --deployer=0x... --manager=0x... --vault=0x... --owner=0x... [--fee-bips=100]");
  process.exit(1);
}
if (feeBips < 0n || feeBips > 2000n) {
  console.error("--fee-bips must be between 0 and 2000");
  process.exit(1);
}
if (max <= 0n) {
  console.error("--max must be positive");
  process.exit(1);
}

const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
const abiCoder = AbiCoder.defaultAbiCoder();
const constructorArgs = abiCoder.encode(["address", "address", "address", "uint16"], [manager, vault, owner, feeBips]);
const initCode = concat([artifact.bytecode.object ?? artifact.bytecode, constructorArgs]);
const initCodeHash = keccak256(initCode);

for (let i = 0n; i < max; i++) {
  const salt = toBeHex(i, 32);
  const predicted = getCreate2Address(deployer, salt, initCodeHash);
  const low = BigInt(dataSlice(predicted, 18));
  if ((low & mask) === flags) {
    console.log(JSON.stringify({ salt, predicted, initCodeHash }, null, 2));
    process.exit(0);
  }
}

console.error(`No salt found in ${max} attempts`);
process.exit(2);
