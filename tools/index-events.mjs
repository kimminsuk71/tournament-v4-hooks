#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { JsonRpcProvider, getAddress, isAddress } from "ethers";
import { buildBoardPayload, eventTopics } from "./index-events-core.mjs";

function arg(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((item) => item.startsWith(prefix));
  if (found) return found.slice(prefix.length);
  const env = process.env[name.toUpperCase().replaceAll("-", "_")];
  return env ?? fallback;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function parseAddress(name) {
  const value = arg(name);
  if (!value || !isAddress(value)) fail(`--${name} must be a valid address`);
  return getAddress(value);
}

function parseBlockNumber(name, fallback) {
  const value = arg(name, fallback);
  if (!/^\d+$/.test(value)) fail(`--${name} must be a non-negative integer`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) fail(`--${name} must be a safe integer`);
  return parsed;
}

const rpcUrl = arg("rpc-url");
const hook = parseAddress("hook");
const vault = parseAddress("vault");
const fromBlock = parseBlockNumber("from-block", "0");
const out = arg("out", "frontend/generated/board-data.json");
const teamsPath = arg("teams", "config/teams.json");

if (!rpcUrl) {
  console.error("Usage: index-events --rpc-url=... --hook=0x... --vault=0x... [--from-block=0]");
  process.exit(1);
}

let teams;
try {
  teams = JSON.parse(readFileSync(teamsPath, "utf8"));
} catch (error) {
  fail(`failed to read ${teamsPath}: ${error.message}`);
}

const provider = new JsonRpcProvider(rpcUrl);
const latest = await provider.getBlockNumber();
const logs = await provider.getLogs({
  fromBlock,
  toBlock: latest,
  address: [hook, vault],
  topics: [[eventTopics.PoolRegistered, eventTopics.PoolRegistrationRemoved, eventTopics.SwapFeeRouted, eventTopics.BuybackBurned]]
});

let payload;
try {
  payload = buildBoardPayload({ teams, logs, hook, vault, fromBlock, toBlock: latest });
} catch (error) {
  fail(error.message);
}

mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(payload, null, 2));
console.log(`Wrote ${out}`);
