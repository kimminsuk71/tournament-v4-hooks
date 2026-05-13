# tournament-v4-hooks

Experimental Uniswap v4 hook system for a tournament-themed token board.

It implements the useful part of the World Cup Coins style design as contracts:

- `HubToken`: the tournament-wide token that gets bought and burned.
- `TeamToken`: ERC20 token for each team.
- `TeamTokenFactory`: owner-controlled team token launcher.
- `TournamentHook`: registered v4 pools pay an extra swap fee.
- `BuybackVault`: holds buyback inventory, routes treasury share, executes buyback-and-burn.

## Mechanism

For every exact-input swap on a registered pool:

1. `TournamentHook.afterSwap` computes a hook fee from the output token.
2. The hook pulls that fee from the v4 `PoolManager`.
3. 50% is deposited into `BuybackVault.pendingBuyback`.
4. 50% is sent to `treasury`.
5. The owner or keeper later calls `executeBuybackAndBurn` with a buyback executor.

Exact-output swaps currently revert in the hook. Uniswap v4 `afterSwapReturnDelta` charges the unspecified currency; for exact-output swaps that would be the input token, which does not match this prototype's "fee from output token" rule.

This makes the hub-token burn path explicit and testable instead of relying on a website promise.

## Build

```bash
git submodule update --init --recursive
npm install
forge build
forge test -vv
```

Current test coverage:

- team token factory creation and duplicate guard
- token constructor zero-owner and zero-supply guards
- token constructor empty metadata guards
- hook swap fee routing
- disabled hook entrypoints revert
- ownership transfer and registered-pool state guards
- buyback executor path and hub token burn
- exact-output rejection
- pool registration hook-address mismatch rejection
- pool registration v4 fee and tick-spacing rejection
- duplicate pool registration and duplicate removal rejection
- buyback executor underpayment rejection
- EOA buyback executor rejection
- EOA hook binding rejection
- direct burn path when pending buyback inventory is already `HUB`
- vault ownership renounce rejection
- zero-amount fee deposit rejection
- extreme signed swap delta rejection without arithmetic panic
- EOA manager, vault, and hub-token dependency rejection
- CREATE2 hook salt mining and deployed address prediction
- CREATE2 init code that deploys no runtime code rejection

## Important v4 Note

Real Uniswap v4 deployment must use a hook address with the correct permission bits. This hook needs:

- `afterSwap`
- `afterSwapReturnDelta`

`DeployWithMinedHook` deploys `HookDeployer`, mines a CREATE2 salt, and deploys `TournamentHook` to an address whose low 14 permission bits equal `0x44`.

The `TournamentHook` constructor validates these permission bits, so direct `new TournamentHook(...)` deployment is expected to revert unless the resulting address already has the required low bits. Use `DeployWithMinedHook` for any real v4-compatible deployment.

## Audit Notes

This is still an experiment, but the current implementation enforces the main invariants in code:

- only the configured v4 `PoolManager` can call `afterSwap`
- only pools whose `PoolKey.hooks` equals the deployed hook can be registered
- registered pool currencies must be non-native ERC20 addresses and sorted as v4 expects
- registered pools must use a valid v4 static fee or dynamic fee sentinel and tick spacing in the v4 range
- fee bips are capped at 20%
- hook fee accounting rejects non-output swap deltas
- hook ownership transfers emit `OwnershipTransferred` and preserve only-owner enforcement
- pool registration is a one-way state transition until explicit removal; duplicate register/remove calls revert
- `HubToken` and `TeamToken` do not expose owner-only minting after construction
- `HubToken` and `TeamToken` reject empty deployment metadata
- `HookDeployer` is owner-gated to prevent third parties from occupying salts and rejects deployments with empty runtime code
- team token creation rejects zero owner, zero initial supply, and empty metadata
- `TeamTokenFactory` ownership cannot be renounced because that would permanently disable team creation
- vault hook address can only be set once and must point to deployed code
- vault ownership cannot be renounced because that would permanently disable buyback execution and treasury updates
- vault rejects fee-on-transfer or rebasing behavior that causes short receipt
- vault rejects EOAs as buyback executors so buybacks must go through contract code
- buyback executors must spend the exact fee-token amount and deliver the exact reported `HUB` amount
- pending `HUB` can be burned directly without routing through an external executor
- the frontend renders generated data through DOM text nodes rather than `innerHTML`
- the event indexer treats `pendingBuyback` as deposits minus burned fee-token inventory
- deployment and indexing scripts validate common malformed inputs before broadcasting or querying
- helper scripts reject out-of-range hook fee settings, invalid addresses, invalid block numbers, zero salt-search windows, and integer casts that would truncate before encoding or broadcasting

Indexer caveat: `BuybackBurned` is keyed by fee token, not pool id, so hub-level pending buyback is authoritative, while per-team pending is only exact when a fee token maps to one registered team pool.

## Testnet Flow

Set the usual broadcast variables first:

```bash
export PRIVATE_KEY=0x...
export RPC_URL=https://...
export POOL_MANAGER=0x...
export TREASURY=0x...
```

Deploy the hub token, vault, team factory, hook deployer, and mined hook:

```bash
forge script script/DeployWithMinedHook.s.sol:DeployWithMinedHook \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Create default team tokens, or override `TEAM_IDS`, `TEAM_NAMES`, `TEAM_SYMBOLS`, and `TEAM_INITIAL_SUPPLY`:

```bash
export TEAM_FACTORY=0x...
forge script script/CreateTeams.s.sol:CreateTeams \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Register an existing Uniswap v4 pool for hook fee routing:

```bash
export HOOK=0x...
export TOKEN_A=0x...
export TOKEN_B=0x...
forge script script/RegisterPool.s.sol:RegisterPool \
  --rpc-url "$RPC_URL" \
  --broadcast
```

After team token addresses exist, copy them into `config/teams.json`, then generate the frontend data file:

```bash
npm run index -- \
  --rpc-url="$RPC_URL" \
  --hook="$HOOK" \
  --vault=0x... \
  --from-block=0
```

The generated board is written to `frontend/generated/board-data.json`. If it is missing, the frontend falls back to `frontend/config.js`.

## Repository Layout

```text
frontend/
  Static tournament market board prototype
src/
  HookDeployer.sol
  BuybackVault.sol
  HubToken.sol
  TeamToken.sol
  TeamTokenFactory.sol
  TournamentHook.sol
script/
  DeployWithMinedHook.s.sol
  CreateTeams.s.sol
  RegisterPool.s.sol
tools/
  mine-hook-salt.mjs
  index-events.mjs
test/
  HookDeployer.t.sol
  TournamentHook.t.sol
docs/
  design.md
```

The frontend is static. Open `frontend/index.html` directly for the fallback sample, or serve the folder with any static file server so it can fetch `frontend/generated/board-data.json`.
