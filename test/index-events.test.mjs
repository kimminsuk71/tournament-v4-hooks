import { test } from "node:test";
import assert from "node:assert/strict";
import { Interface } from "ethers";
import { buildBoardPayload, normalizeTeamsConfig } from "../tools/index-events-core.mjs";

const hook = "0x0000000000000000000000000000000000000044";
const vault = "0x0000000000000000000000000000000000000001";
const teamToken = "0x0000000000000000000000000000000000000100";
const quoteToken = "0x0000000000000000000000000000000000000200";
const poolA = "0x" + "01".repeat(32);
const poolB = "0x" + "02".repeat(32);

const iface = new Interface([
  "event PoolRegistered(bytes32 indexed poolId,address indexed currency0,address indexed currency1)",
  "event PoolRegistrationRemoved(bytes32 indexed poolId)",
  "event SwapFeeRouted(bytes32 indexed poolId,address indexed feeToken,uint256 feeAmount,uint256 buybackAmount,uint256 treasuryAmount)"
]);

function eventLog(eventName, args) {
  const encoded = iface.encodeEventLog(iface.getEvent(eventName), args);
  return {
    data: encoded.data,
    topics: encoded.topics
  };
}

function teamsConfig(extraTeams = []) {
  return {
    hub: { symbol: "HUB", decimals: 18 },
    teams: [
      {
        id: "alpha",
        name: "Alpha FC",
        symbol: "ALPHA",
        countryCode: "us",
        token: teamToken,
        decimals: 0
      },
      ...extraTeams
    ],
    matches: []
  };
}

test("indexer aggregates all pools for a team token", () => {
  const payload = buildBoardPayload({
    teams: teamsConfig(),
    logs: [
      eventLog("PoolRegistered", [poolA, teamToken, quoteToken]),
      eventLog("PoolRegistered", [poolB, teamToken, quoteToken]),
      eventLog("SwapFeeRouted", [poolA, quoteToken, 12n, 5n, 7n]),
      eventLog("SwapFeeRouted", [poolB, quoteToken, 20n, 9n, 11n])
    ],
    hook,
    vault,
    fromBlock: 0,
    toBlock: 4,
    generatedAt: new Date("2026-05-13T00:00:00.000Z")
  });

  const [team] = payload.teams;
  assert.equal(team.buybackRaw, "14");
  assert.equal(team.treasuryRaw, "18");
  assert.equal(team.poolStatus, "active");
  assert.equal(team.poolCount, 2);
  assert.equal(team.activePoolCount, 2);
  assert.deepEqual(team.poolIds, [poolA, poolB]);
  assert.deepEqual(team.activePoolIds, [poolA, poolB]);
  assert.equal(payload.hub.pendingBuybackRaw, "14");
  assert.equal(payload.hub.treasuryRoutedRaw, "18");
  assert.equal(payload.hub.totalBurnedRaw, "0");
});

test("indexer marks removed-only multi-pool team as removed while preserving gross inventory", () => {
  const payload = buildBoardPayload({
    teams: teamsConfig(),
    logs: [
      eventLog("PoolRegistered", [poolA, teamToken, quoteToken]),
      eventLog("PoolRegistered", [poolB, teamToken, quoteToken]),
      eventLog("SwapFeeRouted", [poolA, quoteToken, 12n, 5n, 7n]),
      eventLog("SwapFeeRouted", [poolB, quoteToken, 20n, 9n, 11n]),
      eventLog("PoolRegistrationRemoved", [poolA]),
      eventLog("PoolRegistrationRemoved", [poolB])
    ],
    hook,
    vault,
    fromBlock: 0,
    toBlock: 6,
    generatedAt: new Date("2026-05-13T00:00:00.000Z")
  });

  const [team] = payload.teams;
  assert.equal(team.poolStatus, "removed");
  assert.equal(team.poolCount, 2);
  assert.equal(team.activePoolCount, 0);
  assert.equal(team.buybackRaw, "14");
  assert.equal(team.treasuryRaw, "18");
});

test("indexer can attribute fee events from configured pool ids without registration logs", () => {
  const config = teamsConfig();
  config.teams[0].poolIds = [poolA, poolB];
  const payload = buildBoardPayload({
    teams: config,
    logs: [
      eventLog("SwapFeeRouted", [poolA, quoteToken, 12n, 5n, 7n]),
      eventLog("SwapFeeRouted", [poolB, quoteToken, 20n, 9n, 11n])
    ],
    hook,
    vault,
    fromBlock: 100,
    toBlock: 104,
    generatedAt: new Date("2026-05-13T00:00:00.000Z")
  });

  const [team] = payload.teams;
  assert.equal(team.buybackRaw, "14");
  assert.equal(team.treasuryRaw, "18");
  assert.equal(team.poolStatus, "active");
  assert.equal(team.poolCount, 2);
  assert.equal(team.activePoolCount, 2);
});

test("indexer rejects duplicate configured team tokens", () => {
  assert.throws(
    () =>
      normalizeTeamsConfig(
        teamsConfig([
          {
            id: "bravo",
            name: "Bravo",
            symbol: "BRAVO",
            countryCode: "br",
            token: teamToken,
            decimals: 18
          }
        ])
      ),
    /duplicate team token/
  );
});

test("indexer rejects duplicate configured team pools", () => {
  const config = teamsConfig([
    {
      id: "bravo",
      name: "Bravo",
      symbol: "BRAVO",
      countryCode: "br",
      token: "0x0000000000000000000000000000000000000300",
      poolId: poolA,
      decimals: 18
    }
  ]);
  config.teams[0].poolId = poolA;

  assert.throws(() => normalizeTeamsConfig(config), /duplicate team pool/);
});

test("indexer rejects duplicate configured team pools without team tokens", () => {
  const config = teamsConfig([
    {
      id: "bravo",
      name: "Bravo",
      symbol: "BRAVO",
      countryCode: "br",
      poolId: poolA,
      decimals: 18
    }
  ]);
  config.teams[0].token = null;
  config.teams[0].poolId = poolA;

  assert.throws(() => normalizeTeamsConfig(config), /duplicate team pool/);
});

test("indexer rejects invalid configured team token", () => {
  assert.throws(
    () =>
      normalizeTeamsConfig(
        teamsConfig([
          {
            id: "bravo",
            name: "Bravo",
            symbol: "BRAVO",
            countryCode: "br",
            token: "not-an-address",
            decimals: 18
          }
        ])
      ),
    /must be a valid address or null/
  );
});

test("indexer rejects malformed configured pool ids", () => {
  const config = teamsConfig();
  config.teams[0].poolId = "0x1234";

  assert.throws(() => normalizeTeamsConfig(config), /must be a bytes32 hex pool id or null/);
});
