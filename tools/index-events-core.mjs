import { Interface, formatUnits, getAddress, isAddress } from "ethers";

export const eventTopics = {
  PoolRegistered: "0xfafdbdd88ac30f0aa936e576be61816ea751908540523fa81b80c4a406ad7bec",
  PoolRegistrationRemoved: "0x34db8fb641371e4d1f617ea322484aaf93cbbe3a381e2cc5e6a93c103eb17323",
  SwapFeeRouted: "0x4693228d48dff715c567f44801f984da60a8aa6e4c865d7fd100aac32dea4f0e",
  BuybackBurned: "0x98320b0c5f9ec952b18c16e025f7105f6e7625184dfe46f55df93588a7cf5522"
};

export const eventInterface = new Interface([
  "event PoolRegistered(bytes32 indexed poolId,address indexed currency0,address indexed currency1)",
  "event PoolRegistrationRemoved(bytes32 indexed poolId)",
  "event SwapFeeRouted(bytes32 indexed poolId,address indexed feeToken,uint256 feeAmount,uint256 buybackAmount,uint256 treasuryAmount)",
  "event BuybackBurned(address indexed feeToken,address indexed executor,uint256 feeAmountIn,uint256 hubAmountBurned)"
]);

export function normalizeOptionalAddress(value, label) {
  if (value == null || value === "") return null;
  if (!isAddress(value)) throw new Error(`${label} must be a valid address or null`);
  return getAddress(value).toLowerCase();
}

export function parseDecimals(value, label) {
  const decimals = value ?? 18;
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 255) {
    throw new Error(`${label} must be an integer between 0 and 255`);
  }
  return decimals;
}

export function normalizePoolId(value, label) {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(value)) {
    throw new Error(`${label} must be a bytes32 hex pool id or null`);
  }
  return value.toLowerCase();
}

function normalizeConfiguredPoolIds(team) {
  const ids = [];
  const label = team.id ?? team.name ?? "unknown team";
  const primary = normalizePoolId(team.poolId, `teams[].poolId for ${label}`);
  if (primary) ids.push(primary);
  if (team.poolIds != null) {
    if (!Array.isArray(team.poolIds)) throw new Error(`teams[].poolIds for ${label} must be an array`);
    for (const [index, poolId] of team.poolIds.entries()) {
      const normalized = normalizePoolId(poolId, `teams[].poolIds[${index}] for ${label}`);
      if (normalized) ids.push(normalized);
    }
  }
  return [...new Set(ids)];
}

export function normalizeTeamsConfig(teams) {
  if (!Array.isArray(teams.teams) || !teams.hub || !Array.isArray(teams.matches)) {
    throw new Error("teams config must contain hub, teams[], and matches[]");
  }
  const hubDecimals = parseDecimals(teams.hub.decimals, "hub.decimals");
  const normalizedTeams = teams.teams.map((team) => ({
    ...team,
    token: normalizeOptionalAddress(team.token, `teams[].token for ${team.id ?? team.name ?? "unknown team"}`),
    configuredPoolIds: normalizeConfiguredPoolIds(team),
    decimals: parseDecimals(team.decimals, `teams[].decimals for ${team.id ?? team.name ?? "unknown team"}`)
  }));
  const tokenOwners = new Map();
  const poolOwners = new Map();
  for (const team of normalizedTeams) {
    const label = team.id ?? team.name ?? "unknown team";
    if (team.token) {
      if (tokenOwners.has(team.token)) {
        throw new Error(`duplicate team token ${team.token} for ${tokenOwners.get(team.token)} and ${label}`);
      }
      tokenOwners.set(team.token, label);
    }
    for (const poolId of team.configuredPoolIds) {
      if (poolOwners.has(poolId)) {
        throw new Error(`duplicate team pool ${poolId} for ${poolOwners.get(poolId).label} and ${label}`);
      }
      poolOwners.set(poolId, { label, token: team.token });
    }
  }
  return { hubDecimals, normalizedTeams, teamTokens: new Set(tokenOwners.keys()), poolOwners };
}

export function buildBoardPayload({ teams, logs, hook, vault, fromBlock, toBlock, generatedAt = new Date() }) {
  const { hubDecimals, normalizedTeams, teamTokens, poolOwners } = normalizeTeamsConfig(teams);
  const byPool = new Map();
  let totalTreasury = 0n;
  let totalBurned = 0n;
  const burnedByFeeToken = new Map();

  for (const log of logs) {
    const parsed = eventInterface.parseLog(log);
    if (parsed.name === "PoolRegistered") {
      const poolId = parsed.args.poolId;
      const currency0 = parsed.args.currency0.toLowerCase();
      const currency1 = parsed.args.currency1.toLowerCase();
      const teamToken = teamTokens.has(currency0) ? currency0 : teamTokens.has(currency1) ? currency1 : null;
      const quoteToken = teamToken === currency0 ? currency1 : currency0;
      const existing = byPool.get(poolId) ?? {};
      byPool.set(poolId, { ...existing, poolId, teamToken, quoteToken, registered: true });
    }
    if (parsed.name === "PoolRegistrationRemoved") {
      const poolId = parsed.args.poolId;
      const existing = byPool.get(poolId) ?? { poolId };
      byPool.set(poolId, { ...existing, registered: false });
    }
    if (parsed.name === "SwapFeeRouted") {
      const poolId = parsed.args.poolId;
      const existing = byPool.get(poolId) ?? { poolId };
      existing.teamToken ??= poolOwners.get(poolId.toLowerCase())?.token ?? null;
      existing.feeToken = parsed.args.feeToken.toLowerCase();
      existing.feeAmount = (existing.feeAmount ?? 0n) + parsed.args.feeAmount;
      existing.buyback = (existing.buyback ?? 0n) + parsed.args.buybackAmount;
      existing.treasury = (existing.treasury ?? 0n) + parsed.args.treasuryAmount;
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

  const enriched = normalizedTeams.map((team) => {
    const { configuredPoolIds, ...publicTeam } = team;
    const token = team.token ?? "";
    const configuredPools = new Set(configuredPoolIds);
    const pools = [...byPool.values()].filter(
      (item) => (token && item.teamToken === token) || configuredPools.has(item.poolId.toLowerCase())
    );
    const activePools = pools.filter((item) => item.registered !== false);
    const poolStatus = activePools.length !== 0 ? "active" : pools.length !== 0 ? "removed" : "unregistered";
    const grossBuyback = sumBigInt(pools, (item) => item.buyback ?? 0n);
    const treasury = sumBigInt(pools, (item) => item.treasury ?? 0n);
    return {
      ...publicTeam,
      poolId: activePools[0]?.poolId ?? pools[0]?.poolId ?? team.poolId ?? null,
      poolIds: pools.map((item) => item.poolId),
      activePoolIds: activePools.map((item) => item.poolId),
      poolStatus,
      poolCount: pools.length,
      activePoolCount: activePools.length,
      buybackRaw: grossBuyback.toString(),
      treasuryRaw: treasury.toString(),
      buybackDisplay: formatUnits(grossBuyback, team.decimals),
      treasuryDisplay: formatUnits(treasury, team.decimals)
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

  return {
    generatedAt: generatedAt.toISOString(),
    fromBlock,
    toBlock,
    hook,
    vault,
    hub: {
      ...teams.hub,
      totalBurnedRaw: totalBurned.toString(),
      pendingBuybackRaw: pendingBuybackTotal.toString(),
      treasuryRoutedRaw: totalTreasury.toString(),
      decimals: hubDecimals,
      totalBurnedDisplay: formatUnits(totalBurned, hubDecimals),
      pendingBuybackDisplay: formatUnits(pendingBuybackTotal, hubDecimals),
      treasuryRoutedDisplay: formatUnits(totalTreasury, hubDecimals)
    },
    teams: enriched,
    matches: teams.matches
  };
}

function sumBigInt(items, selector) {
  return items.reduce((total, item) => total + selector(item), 0n);
}
