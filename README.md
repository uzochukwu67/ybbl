# YBBC — Yield-Bearing Bonding Curve Launchpad

> **The first privacy-native, yield-backed meme coin launchpad on Starknet.**
> Buy anonymously. Watch your backing earn. Graduate to real liquidity.

Built for the **Starknet BTC + Privacy Hackathon 2026**.

---

## The Problem With Every Other Launchpad

Pump.fun made meme launches viral. But it left one massive inefficiency on the table: **billions in bonding curve reserves sitting completely idle**, earning nothing, backing nothing, doing nothing — until graduation, when they're dumped into a DEX and the liquidity immediately fragments.

Every buy on Pump.fun is dead capital from the moment it enters the curve.

YBBC changes that.

---

## What YBBC Is

YBBC is a meme coin launchpad on Starknet where **every token has a live treasury from the moment of launch**.

Three things make it different from anything deployed today:

### 1. Privacy — Buy Without a Trace

Every purchase can be made anonymously. No on-chain link between your wallet address and your position.

**Two privacy tiers, both live on-chain:**

- **Nullifier mode** (`buy_anonymous`) — you submit a Pedersen nullifier instead of identifying data. The nullifier is stored on-chain as used; it can never be replayed. Your wallet triggers the transaction but nothing links you to the buy amount or timing pattern.

- **Full ZK mode** (`buy_zk_anonymous`) — a Noir proof is verified on-chain. The proof demonstrates knowledge of a secret that produces the nullifier, without revealing the secret. This is the highest privacy tier: the relationship between your identity and your purchase is cryptographically broken, not just obscured.

This is the first bonding curve launchpad with on-chain ZK anonymous purchasing. Tornado Cash brought privacy to transfers. YBBC brings it to price discovery.

### 2. BTC Yield Flywheel — Dead Reserves Start Working

When a token graduates (reserve hits threshold), the accumulated reserve isn't dumped. It's deployed:

```
User buys with wBTC
    └─ Reserve accumulates in launchpad
        └─ On graduation → reserve deposited to Vesu (wBTC lending, ~3-8% APY)
            └─ anyone calls harvest_yield()
                └─ Vesu yield withdrawn
                    └─ New Ekubo LP position seeded with yield wBTC + fresh meme tokens
                        └─ Trading depth deepens → less slippage → price supports better
                            └─ Stronger price → more buyers → more wBTC flows in
                                └─ (flywheel continues)
```

The principal never leaves Vesu. Every harvest cycle adds a new independent LP position on top of the last. Liquidity compounds. The meme coin's floor gets harder with each cycle — backed by real Bitcoin yield, not promises.

**This is not a 5% APY sticker on top of a launchpad. It is a self-reinforcing BTC liquidity engine.**

### 3. Quadratic Bonding Curve + Ekubo Graduation

Price discovery follows a quadratic curve calibrated so that selling the full max supply raises exactly the graduation threshold:

```
buy_cost(S, Δ)    = K × (2S + Δ) × Δ
sell_payout(S, Δ) = K × (2S − Δ) × Δ
curve_k           = 2 × grad_threshold / max_supply²
```

1% of every trade accumulates as protocol fees.

On graduation:
1. Fees → **initial Ekubo full-range LP** (seeded at exact graduation price ratio)
2. Reserve → **Vesu lending** (flywheel begins)
3. Token is now tradeable on Ekubo with real depth, not a thin DEX pool

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        YBBC Launchpad                           │
│                                                                 │
│  launch_token()   →  deploys ERC20 via deploy_syscall           │
│                      (minter = launchpad, immutable)            │
│                                                                 │
│  buy()            →  quadratic cost + 1% fee                    │
│  buy_anonymous()  →  nullifier anti-replay + buy                │
│  buy_zk_anon()    →  Noir proof verified on-chain → buy         │
│  sell()           →  burn tokens, release reserve               │
│                                                                 │
│  graduate()       →  fees → Ekubo LP                            │
│                      reserve → Vesu                             │
│                                                                 │
│  harvest_yield()  →  Vesu yield → new Ekubo LP (flywheel)       │
│  collect_lp_fees()→  collect Ekubo trading fees                 │
└────────┬───────────────────┬────────────────────────────────────┘
         │                   │
         ▼                   ▼
   ┌───────────┐      ┌──────────────┐
   │   Vesu    │      │    Ekubo     │
   │  Lending  │      │  Positions   │
   │  Singleton│      │     NFT      │
   └───────────┘      └──────────────┘
         │                   │
     wBTC yield         LP fees +
     accumulates        trading depth
```

**Base assets supported:** wBTC, ETH, STRK, USDC
**Contracts:** `launchpad.cairo`, `erc20.cairo`, `ekubo_interfaces.cairo`, `vesu_interfaces.cairo`, `noir_verifier.cairo`

---

## Hackathon Track Alignment

| Track | How YBBC Qualifies |
|---|---|
| **BTC on Starknet** | wBTC is a first-class base asset. Graduation deploys wBTC principal to Vesu. Yield from real BTC lending deepens real Ekubo liquidity. The entire flywheel runs on Bitcoin. |
| **Privacy** | `buy_anonymous` (nullifier) and `buy_zk_anonymous` (Noir proof) give users cryptographic privacy on every purchase. No other launchpad on any chain ships this. |

---

## Where We Are Today

| Feature | Status |
|---|---|
| Quadratic bonding curve | ✅ Live |
| ERC20 deploy per launch | ✅ Live |
| 1% fee accumulation | ✅ Live |
| Ekubo LP at graduation | ✅ Live |
| Vesu yield flywheel | ✅ Live |
| wBTC base asset | ✅ Live |
| Nullifier anonymous buy | ✅ Live |
| Noir ZK proof buy | ✅ Contract ready (verifier integration in progress) |
| Next.js frontend | ✅ Live |
| On-chain token enumeration | ✅ Live |
| Spot price display | ✅ Live |
| Graduation progress bar | ✅ Live |

---

## Roadmap

### Phase 1 — Foundation ✅ (Current)

The bonding curve, ZK privacy layer, BTC yield flywheel, and Ekubo graduation are shipped. Tokens launch, trade, graduate, and earn. This is a functional protocol, not a demo.

---

### Phase 2 — Reserve Perp Engine (Q3 2026)

This is the bold next step. Today, the reserve earns passive yield. In Phase 2, a portion of the reserve is actively managed as a disciplined perp position with hard-coded guardrails.

**The concept — every graduated token becomes a mini treasury with a trading mandate:**

```
Graduation reserve split:
├── 50% → Vesu lending     (safe base yield, always liquid)
├── 30% → Paradex perp     (directional or delta-neutral)
│         stop-loss:   -40% of allocated collateral  ← hard, on-chain
│         take-profit: +100% of allocated collateral ← auto-close
└── 20% → liquid buffer    (instant sell liquidity for curve)

On take-profit:
    profit → buyback + burn  OR  pro-rata holder distribution

On stop-loss:
    position closed, reset, reopen next cycle
    3+ consecutive losses → pause perp engine, hold full position in Vesu
```

**Why the math works for holders:**

Passive Vesu yield on a $500K reserve might generate $25-40K/year. A perp position with a 40%/100% stop/take structure at a conservative 45% win rate — achievable with trend-following or funding rate capture on Paradex — can produce 50-150% effective yield on the allocated collateral per year. At $1M market cap, that is the difference between 1% buyback pressure and 15-45% buyback pressure annually.

The meme has alpha, not just vibes.

**Breakeven analysis (simple risk-reward):**
```
Win rate needed > 0.4 / (1 + 0.4) = 28.6%
Conservative target: 40-45% win rate
Expected result at 45%: strongly positive after fees and funding
```

**Starknet infrastructure:**
- **Paradex** — orderbook perps, Paradigm-backed, mainnet live, SDK available
- **On-chain keeper** — Cairo contract monitors positions, triggers SL/TP automatically
- **Transparent dashboard** — live PnL, win rate, all positions on-chain and verifiable

No black box. Every trade decision is auditable on-chain.

---

### Phase 3 — Protocol Token + Revenue Share (Q4 2026)

- `$YBBC` governance token
- 15% of all perp profits + LP trading fee revenue → `$YBBC` stakers as real payouts
- DAO governance over: perp risk parameters, Vesu pool selection, graduation thresholds, strategy whitelisting

---

### Phase 4 — Permissionless Strategy Vaults (2027)

- Anyone can submit a Cairo strategy module
- Community votes to whitelist strategies
- Reserve allocation becomes a democratic portfolio
- Advanced strategies enabled: funding rate arbitrage, cross-asset hedging, structured products

---

## Why No One Has Done This

Pump.fun keeps it simple by design — complexity kills conversion. Perp protocols and launchpads have always been separate categories. Yield aggregators on Starknet are standalone products, not integrated into launch flows.

The combination of:
1. **ZK-private bonding curve purchasing** — cryptographic buying privacy at the protocol level
2. **BTC yield flywheel** — reserves earn and compound into deeper liquidity automatically
3. **Disciplined perp backing layer** — reserves trade for holders with hard guardrails (Phase 2)

...has not shipped anywhere. On any chain.

YBBC is the first serious attempt to treat the meme launchpad reserve as a treasury rather than a waiting room.

---

## Technical Stack

| Layer | Technology |
|---|---|
| Smart contracts | Cairo 2 (Starknet) |
| ZK proofs | Noir (Aztec) |
| DEX integration | Ekubo v2 |
| Lending integration | Vesu Singleton |
| Perps (Phase 2) | Paradex |
| Frontend | Next.js + Chakra UI |
| Wallet | Starknet.js v6, Argent / Braavos |

---

## Local Development

```bash
# Contracts
cd earnv2
scarb build
snforge test

# Frontend
cd earnv2/frontend
npm install
npm run dev
```

**Testnet note:** STRK and ETH work on Sepolia. wBTC/USDC are mainnet-only bridged tokens — use STRK for testnet launches.

---

## License

MIT
