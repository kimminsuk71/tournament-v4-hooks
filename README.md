# tournament-v4-hooks

Experimental Uniswap v4 hook system for a tournament-themed token board.

It implements the useful part of the World Cup Coins style design as contracts:

- `HubToken`: the tournament-wide token that gets bought and burned.
- `TeamToken`: ERC20 token for each team.
- `TeamTokenFactory`: owner-controlled team token launcher.
- `TournamentHook`: registered v4 pools pay an extra swap fee.
- `BuybackVault`: holds buyback inventory, routes treasury share, executes buyback-and-burn.

## Mechanism

For every swap on a registered pool:

1. `TournamentHook.afterSwap` computes a hook fee from the output token.
2. The hook pulls that fee from the v4 `PoolManager`.
3. 50% is deposited into `BuybackVault.pendingBuyback`.
4. 50% is sent to `treasury`.
5. The owner or keeper later calls `executeBuybackAndBurn` with a buyback executor.

This makes the hub-token burn path explicit and testable instead of relying on a website promise.

## Build

```bash
git submodule update --init --recursive
forge build
forge test -vv
```

Current test coverage:

- team token factory creation and duplicate guard
- hook swap fee routing
- buyback executor path and hub token burn

## Important v4 Note

Real Uniswap v4 deployment must use a hook address with the correct permission bits. This hook needs:

- `afterSwap`
- `afterSwapReturnDelta`

The included tests validate accounting through a mock `PoolManager`; they do not mine a CREATE2 hook address yet.

## Repository Layout

```text
frontend/
  Static tournament market board prototype
src/
  BuybackVault.sol
  HubToken.sol
  TeamToken.sol
  TeamTokenFactory.sol
  TournamentHook.sol
test/
  TournamentHook.t.sol
docs/
  design.md
```

The frontend is static. Open `frontend/index.html` directly, or serve the folder with any static file server.
