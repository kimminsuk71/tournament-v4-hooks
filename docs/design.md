# Tournament v4 Hook Design

This prototype turns a tournament into a tradeable token board:

1. A single hub token represents the whole tournament.
2. Each team gets its own ERC20 token.
3. Official Uniswap v4 pools register with the hook.
4. The hook takes an extra fee from each registered swap.
5. The fee is split between buyback inventory and treasury.
6. A keeper or owner executes a buyback and burns hub tokens.

## On-Chain Flow

```text
swap on registered v4 pool
  -> PoolManager calls TournamentHook.afterSwap
  -> hook computes fee from output token
  -> hook takes fee from PoolManager
  -> hook deposits 50% to BuybackVault
  -> hook routes 50% to treasury
  -> keeper calls BuybackVault.executeBuybackAndBurn
  -> executor swaps fee token into hub token
  -> vault burns hub token
```

The current split is fixed at 50/50 in `TournamentHook`. `feeBips` is owner-configurable and capped at 20% for the experiment.

## Why v4 Hooks

The Pump.fun version is mostly a website plus off-chain promises. A v4 hook makes the fee capture mechanical for every pool that opts into the hook. It does not stop third parties from creating non-hook pools, so the product should clearly mark official pools in the UI.

## Hook Address Caveat

Uniswap v4 derives hook permissions from the low bits of the hook contract address. This implementation uses `afterSwap` and returns an after-swap delta, so production deployment must mine a CREATE2 salt for an address with:

- `AFTER_SWAP_FLAG`
- `AFTER_SWAP_RETURNS_DELTA_FLAG`

The unit tests call `afterSwap` directly through a mock manager because they validate accounting, not CREATE2 address mining.

## Frontend Shape

The website can stay static:

- `teams.json` contains team token addresses and pool ids.
- A worker or API indexes `SwapFeeRouted`, `BuybackBurned`, token prices, and volume.
- The UI ranks team tokens by market cap, volume, and recent match relevance.
- The hub token panel shows total burned and pending buyback inventory.

## Next Implementation Steps

- Add a CREATE2 hook deployer that mines valid permission bits.
- Add a real swap executor using Universal Router or a dedicated v4 route.
- Add pool creation scripts.
- Add a small indexer for events and a static leaderboard frontend.
