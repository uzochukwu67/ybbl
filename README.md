# YBBC — Yield-Bearing Bonding Curve Launchpad

A PumpFun-style meme token launchpad on Starknet where every token launched is backed by **real Bitcoin yield**.

## The BTC-Yield Flywheel

```
User buys meme token with wBTC
         │
         ▼
  wBTC reserve accumulates
  on the bonding curve
         │
         ▼  (reserve ≥ graduation threshold)
  ┌──────────────────────────┐
  │       GRADUATION         │
  │  1. Reserve → Vesu       │  ← wBTC earns 3–5% APY
  │  2. Meme token → Ekubo   │  ← full-range LP seeded
  └──────────────────────────┘
         │
         ▼  (anyone calls harvest_yield)
  ┌──────────────────────────┐
  │     YIELD HARVEST        │
  │  1. Withdraw accrued     │
  │     yield from Vesu      │
  │  2. Mint meme tokens at  │
  │     graduation price     │
  │  3. Seed new Ekubo LP    │  ← deepens meme liquidity
  └──────────────────────────┘
         │
         ▼
  More Ekubo LP depth
  → tighter spreads
  → better trading UX
  → more buyers
  → more wBTC flows in
  → more yield generated
  → repeat ♻️
```

### Why wBTC as the Base Asset?

- **wBTC earns real yield** — once graduated to Vesu, the reserve compounds at ~3-5% APY
- **Yield deepens LP** — every harvest cycle adds a new Ekubo full-range position, tightening spreads
- **No inflationary buybacks** — meme tokens minted during harvest are matched by real wBTC yield
- **BTC-native narrative** — the meme token's value is permanently backstopped by Bitcoin productivity

---

## Architecture

### Smart Contracts (`src/`)

| File | Description |
|------|-------------|
| `launchpad.cairo` | Factory + bonding curve + graduation + yield flywheel |
| `erc20.cairo` | Launchable meme token (mint/burn gated to launchpad) |
| `ekubo_interfaces.cairo` | Minimal Ekubo Positions + Core interfaces |

### Bonding Curve Formula (quadratic)

```
buy_cost(S, delta)    = K × (2S + delta) × delta
sell_payout(S, delta) = K × (2S − delta) × delta
```

`K` = curve steepness constant (default: 40), `S` = current supply sold.

1% fee applied on every buy and sell; fees accumulate in the launchpad and are swept to the Ekubo LP at graduation.

### Entry Points

```cairo
fn launch_token(name, symbol, base_asset) -> ContractAddress
fn buy(token, delta, max_cost) -> u256          // returns cost paid
fn sell(token, delta, min_payout) -> u256       // returns payout received
fn buy_anonymous(token, delta, max_cost,        // ZK privacy buy
                 nullifier, proof) -> u256
fn graduate(token)                              // permissionless once eligible
fn harvest_yield(token) -> u256                 // pull Vesu yield → deepen Ekubo LP
fn collect_lp_fees(token)                       // collect Ekubo swap fees
```

### Graduation Flow

1. Reserve accumulates until `reserve >= grad_threshold`
2. `graduate()` is called (permissionless — anyone can trigger it)
3. wBTC reserve is deposited into Vesu (starts earning yield)
4. A full-range Ekubo LP is seeded with wBTC + meme tokens
5. Token is marked graduated — bonding curve trading halts

### Harvest Yield Flow

1. Vesu position accrues yield passively over time
2. Anyone calls `harvest_yield(token)`
3. Only the yield is withdrawn: `yield = current_position − principal`
4. Meme tokens minted at graduation price ratio: `meme_minted = yield × supply / principal`
5. New Ekubo LP position created with yield wBTC + minted meme tokens
6. This permanently deepens the meme token's on-chain liquidity

---

## ZK Anonymous Buys

Built with [Noir](https://noir-lang.org/). Users can buy tokens without linking their wallet identity to the purchase.

```
Prover computes:  nullifier = hash(secret, nonce)
Circuit proves:   knowledge of secret s.t. hash(secret, nonce) == nullifier
On-chain:         nullifier recorded → prevents replay attacks
```

- Circuit: `circuits/anonymous_buy/src/main.nr`
- On-chain verifier: `src/noir_verifier.cairo`

---

## Deployments

### Sepolia Testnet (active)

| Contract | Address | Explorer |
|----------|---------|---------|
| **Launchpad** | `0x04206063d4668834e4968ca66a8eaeb186c7d8b888bd818100c228b3de60981c` | [Voyager](https://sepolia.voyager.online/contract/0x04206063d4668834e4968ca66a8eaeb186c7d8b888bd818100c228b3de60981c) |
| ERC20 class | `0x2d2f4cf49064e879da0b0fb0a3c00d2e1dc3c6e59dfbdc0836da7be6cbfba` | [Voyager](https://sepolia.voyager.online/class/0x0002d2f4cf49064e879da0b0fb0a3c00d2e1dc3c6e59dfbdc0836da7be6cbfba) |
| Launchpad class | `0x4310f81fa33fce36e578f39a9980b0c7bf499cff49aac600557aaa7faa9ad9f` | [Voyager](https://sepolia.voyager.online/class/0x04310f81fa33fce36e578f39a9980b0c7bf499cff49aac600557aaa7faa9ad9f) |
| Ekubo Core | `0x0444a09d96389aa7148f1aada508e30b71299ffe650d9c97fdaae38cb9a23384` | Ekubo |
| Ekubo Positions | `0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5` | Ekubo |

**Deployment tx:** [`0x07bdad26...`](https://sepolia.voyager.online/tx/0x07bdad26075ce5c6aa228017b7bdc4523c55abef1b297fdb448a59a0c789c43c)

> Vesu is not on Sepolia — graduation creates an Ekubo LP but Vesu yield is disabled on testnet.
> Pass `vesu_pool_id = 0` when calling `launch_token` on Sepolia.

### Mainnet Protocol Addresses (for production deployment)

| Contract | Address |
|----------|---------|
| Ekubo Positions NFT | `0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067` |
| Ekubo Core | `0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b` |
| wBTC | `0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac` |
| USDC | `0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8` |
| STRK | `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d` |
| Vesu Singleton | TBD — use Genesis pool ID `0x4dc4ea5ec84beddca0f33c4e1b0a6b62d281e0e9b34eaec6a7aa9e54e20e` |

---

## Development

### Prerequisites

- [Scarb](https://docs.swmansion.com/scarb/) v2.6+
- [snforge](https://foundry-rs.github.io/starknet-foundry/) (Starknet Foundry)
- Node.js 18+ (for frontend)

### Build contracts

```bash
cd earnv2
scarb build
```

### Run tests

```bash
# Unit tests (no fork required)
snforge test --filter launchpad_test

# Mainnet fork tests (requires RPC in snfoundry.toml)
snforge test --filter wbtc_fork
snforge test --filter nomock
```

Configure your RPC endpoint in `snfoundry.toml`:

```toml
[profile.default.fork.mainnet]
url = "https://starknet-mainnet.g.alchemy.com/starknet/version/rpc/v0_7/<your-key>"
block_id = { tag = "latest" }
```

### Run frontend

```bash
cd earnv2/frontend
npm install
cp .env.example .env.local   # set NEXT_PUBLIC_LAUNCHPAD_ADDRESS
npm run dev
```

---

## Frontend Pages

| Page | Description |
|------|-------------|
| `/` | Landing — BTC/ZK narrative, flywheel explainer |
| `/explore` | Token grid with graduation progress bars |
| `/launch` | Deploy a new bonding curve token (wBTC default) |
| `/token/[address]` | Chart, buy/sell, graduation, yield harvest |

---

## Security Notes

- Bonding curve slippage is enforced via `max_cost` (buy) and `min_payout` (sell) — always set these
- ZK nullifiers prevent replay attacks in anonymous buy flow
- `harvest_yield` only withdraws accrued yield — the Vesu principal is never touched
- `graduate()` is permissionless but idempotent (fires exactly once per token)
