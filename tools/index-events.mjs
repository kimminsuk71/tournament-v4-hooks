#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { Interface, JsonRpcProvider, formatUnits } from "ethers";

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

const rpcUrl = arg("rpc-url");
const hook = arg("hook");
const vault = arg("vault");
const fromBlock = Number(arg("from-block", "0"));
const out = arg("out", "frontend/generated/board-data.json");
const teamsPath = arg("teams", "config/teams.json");

if (!rpcUrl || !hook || !vault) {
  console.error("Usage: index-events --rpc-url=... --hook=0x... --vault=0x... [--from-block=0]");
  process.exit(1);
}

const teams = JSON.parse(readFileSync(teamsPath, "utf8"));
const provider = new JsonRpcProvider(rpcUrl);
const latest = await provider.getBlockNumber();
const iface = new Interface([
  "event PoolRegistered(bytes32 indexed poolId,address indexed teamToken,address indexed quoteToken)",
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

for (const log of logs) {
  const parsed = iface.parseLog(log);
  if (parsed.name === "PoolRegistered") {
    const poolId = parsed.args.poolId;
    const teamToken = parsed.args.teamToken.toLowerCase();
    const existing = byPool.get(poolId) ?? {};
    byPool.set(poolId, { ...existing, poolId, teamToken, quoteToken: parsed.args.quoteToken.toLowerCase() });
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
    totalBurned += parsed.args.hubAmountBurned;
  }
}

const enriched = teams.teams.map((team) => {
  const token = (team.token ?? "").toLowerCase();
  const pool = [...byPool.values()].find((item) => item.teamToken === token || item.quoteToken === token);
  return {
    ...team,
    poolId: pool?.poolId ?? team.poolId ?? null,
    buybackRaw: pool?.buyback?.toString() ?? "0",
    treasuryRaw: pool?.treasury?.toString() ?? "0",
    buybackDisplay: formatUnits(pool?.buyback ?? 0n, team.decimals ?? 18),
    treasuryDisplay: formatUnits(pool?.treasury ?? 0n, team.decimals ?? 18)
  };
});

const payload = {
  generatedAt: new Date().toISOString(),
  fromBlock,
  toBlock: latest,
  hook,
  vault,
  hub: {
    ...teams.hub,
    totalBurnedRaw: totalBurned.toString(),
    pendingBuybackRaw: totalBuyback.toString(),
    treasuryRoutedRaw: totalTreasury.toString(),
    totalBurnedDisplay: formatUnits(totalBurned, teams.hub.decimals ?? 18),
    pendingBuybackDisplay: formatUnits(totalBuyback, teams.hub.decimals ?? 18),
    treasuryRoutedDisplay: formatUnits(totalTreasury, teams.hub.decimals ?? 18)
  },
  teams: enriched,
  matches: teams.matches
};

mkdirSync(out.split("/").slice(0, -1).join("/"), { recursive: true });
writeFileSync(out, JSON.stringify(payload, null, 2));
console.log(`Wrote ${out}`);
