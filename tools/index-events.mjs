#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { Interface, JsonRpcProvider, formatUnits, getAddress, isAddress } from "ethers";

const topics = {
  PoolRegistered: "0xfafdbdd88ac30f0aa936e576be61816ea751908540523fa81b80c4a406ad7bec",
  SwapFeeRouted: "0x4693228d48dff715c567f44801f984da60a8aa6e4c865d7fd100aac32dea4f0e",
  BuybackBurned: "0x98320b0c5f9ec952b18c16e025f7105f6e7625184dfe46f55df93588a7cf5522"
};

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
  return Number(value);
}

function normalizeOptionalAddress(value, label) {
  if (value == null || value === "") return null;
  if (!isAddress(value)) fail(`${label} must be a valid address or null`);
  return getAddress(value).toLowerCase();
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

const teams = JSON.parse(readFileSync(teamsPath, "utf8"));
if (!Array.isArray(teams.teams) || !teams.hub || !Array.isArray(teams.matches)) {
  console.error(`${teamsPath} must contain hub, teams[], and matches[]`);
  process.exit(1);
}
const teamTokens = new Set(
  teams.teams
    .map((team) => normalizeOptionalAddress(team.token, `teams[].token for ${team.id ?? team.name ?? "unknown team"}`))
    .filter(Boolean)
);
const provider = new JsonRpcProvider(rpcUrl);
const latest = await provider.getBlockNumber();
const iface = new Interface([
  "event PoolRegistered(bytes32 indexed poolId,address indexed currency0,address indexed currency1)",
  "event SwapFeeRouted(bytes32 indexed poolId,address indexed feeToken,uint256 feeAmount,uint256 buybackAmount,uint256 treasuryAmount)",
  "event BuybackBurned(address indexed feeToken,address indexed executor,uint256 feeAmountIn,uint256 hubAmountBurned)"
]);

const logs = await provider.getLogs({
  fromBlock,
  toBlock: latest,
  address: [hook, vault],
  topics: [[topics.PoolRegistered, topics.SwapFeeRouted, topics.BuybackBurned]]
});

const byPool = new Map();
let totalBuyback = 0n;
let totalTreasury = 0n;
let totalBurned = 0n;
const burnedByFeeToken = new Map();

for (const log of logs) {
  const parsed = iface.parseLog(log);
  if (parsed.name === "PoolRegistered") {
    const poolId = parsed.args.poolId;
    const currency0 = parsed.args.currency0.toLowerCase();
    const currency1 = parsed.args.currency1.toLowerCase();
    const teamToken = teamTokens.has(currency0) ? currency0 : teamTokens.has(currency1) ? currency1 : null;
    const quoteToken = teamToken === currency0 ? currency1 : currency0;
    const existing = byPool.get(poolId) ?? {};
    byPool.set(poolId, { ...existing, poolId, teamToken, quoteToken });
  }
  if (parsed.name === "SwapFeeRouted") {
    const poolId = parsed.args.poolId;
    const existing = byPool.get(poolId) ?? { poolId };
    existing.feeToken = parsed.args.feeToken.toLowerCase();
    existing.feeAmount = (existing.feeAmount ?? 0n) + parsed.args.feeAmount;
    existing.buyback = (existing.buyback ?? 0n) + parsed.args.buybackAmount;
    existing.treasury = (existing.treasury ?? 0n) + parsed.args.treasuryAmount;
    totalBuyback += parsed.args.buybackAmount;
    totalTreasury += parsed.args.treasuryAmount;
    byPool.set(poolId, existing);
  }
  if (parsed.name === "BuybackBurned") {
    const feeToken = parsed.args.feeToken.toLowerCase();
    const feeAmountIn = parsed.args.feeAmountIn;
    const hubAmountBurned = parsed.args.hubAmountBurned;
    burnedByFeeToken.set(feeToken, (burnedByFeeToken.get(feeToken) ?? 0n) + feeAmountIn);
    totalBurned += hubAmountBurned;
  }
}

const enriched = teams.teams.map((team) => {
  const token = (team.token ?? "").toLowerCase();
  const pool = token ? [...byPool.values()].find((item) => item.teamToken === token) : null;
  const grossBuyback = pool?.buyback ?? 0n;
  const burnedFeeAmount = pool?.feeToken ? burnedByFeeToken.get(pool.feeToken) ?? 0n : 0n;
  const pendingBuyback = grossBuyback > burnedFeeAmount ? grossBuyback - burnedFeeAmount : 0n;
  return {
    ...team,
    poolId: pool?.poolId ?? team.poolId ?? null,
    buybackRaw: pendingBuyback.toString(),
    treasuryRaw: pool?.treasury?.toString() ?? "0",
    buybackDisplay: formatUnits(pendingBuyback, team.decimals ?? 18),
    treasuryDisplay: formatUnits(pool?.treasury ?? 0n, team.decimals ?? 18)
  };
});

const depositedByFeeToken = new Map();
for (const pool of byPool.values()) {
  if (!pool.feeToken) continue;
  depositedByFeeToken.set(pool.feeToken, (depositedByFeeToken.get(pool.feeToken) ?? 0n) + (pool.buyback ?? 0n));
}

let pendingBuybackTotal = 0n;
for (const [feeToken, deposited] of depositedByFeeToken.entries()) {
  const burned = burnedByFeeToken.get(feeToken) ?? 0n;
  pendingBuybackTotal += deposited > burned ? deposited - burned : 0n;
}

const payload = {
  generatedAt: new Date().toISOString(),
  fromBlock,
  toBlock: latest,
  hook,
  vault,
  hub: {
    ...teams.hub,
    totalBurnedRaw: totalBurned.toString(),
    pendingBuybackRaw: pendingBuybackTotal.toString(),
    treasuryRoutedRaw: totalTreasury.toString(),
    totalBurnedDisplay: formatUnits(totalBurned, teams.hub.decimals ?? 18),
    pendingBuybackDisplay: formatUnits(pendingBuybackTotal, teams.hub.decimals ?? 18),
    treasuryRoutedDisplay: formatUnits(totalTreasury, teams.hub.decimals ?? 18)
  },
  teams: enriched,
  matches: teams.matches
};

mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(payload, null, 2));
console.log(`Wrote ${out}`);
