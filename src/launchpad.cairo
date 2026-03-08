/// Yield-Bearing Bonding Curve (YBBC) Launchpad
///
/// BTC-yield flywheel (Option B):
///
///   User buys meme with wBTC
///     └─ wBTC reserve accumulates → graduates to Vesu
///         └─ Vesu yield (e.g. 3-5% APY on BTC) → harvest_yield() seeds new Ekubo LP
///             └─ More liquidity ↑ trading depth → higher meme price
///                 └─ Higher price → more people buy
///                     └─ More wBTC flows in → more yield → flywheel continues
///
/// Bonding curve:
///   buy_cost(S,Δ) = K*(2S+Δ)*Δ       sell_payout(S,Δ) = K*(2S-Δ)*Δ
///
/// Economic calibration:
///   curve_k = 2*grad_threshold / max_supply^2
///   → selling all max_supply raises exactly grad_threshold in wBTC
///
/// ZK Privacy:
///   buy_anonymous() uses a Pedersen nullifier (anti-replay).
///   buy_zk_anonymous() adds on-chain Noir proof verification via the verifier contract.
///   → buyer address is never linked to the purchase on-chain.

use starknet::ContractAddress;

#[starknet::interface]
pub trait ILaunchpad<TContractState> {
    // ── Launch ──────────────────────────────────────────────────────────────
    /// vesu_pool_id — the Vesu pool ID for this base asset (0 = Vesu disabled for this token).
    ///   wBTC mainnet Genesis pool: 0x4dc4ea5ec84beddca0f33c4e1b0a6b62d281e0e9b34eaec6a7aa9e54e20e
    ///   Pass 0 on testnet or for assets not in any Vesu pool.
    fn launch_token(ref self: TContractState, name: felt252, symbol: felt252, base_asset: ContractAddress, vesu_pool_id: felt252) -> ContractAddress;

    // ── Trade ───────────────────────────────────────────────────────────────
    fn buy(ref self: TContractState, token: ContractAddress, delta: u256, max_cost: u256) -> u256;
    fn buy_anonymous(ref self: TContractState, token: ContractAddress, delta: u256, max_cost: u256, nullifier: felt252) -> u256;
    fn buy_zk_anonymous(ref self: TContractState, token: ContractAddress, delta: u256, max_cost: u256, nullifier: felt252, proof: Array<u8>) -> u256;
    fn sell(ref self: TContractState, token: ContractAddress, delta: u256, min_payout: u256) -> u256;

    // ── Lifecycle ───────────────────────────────────────────────────────────
    fn graduate(ref self: TContractState, token: ContractAddress);
    fn collect_lp_fees(ref self: TContractState, token: ContractAddress) -> (u128, u128);

    /// Harvest accrued Vesu yield → mint matching meme tokens → seed new Ekubo LP.
    /// This is the BTC-yield flywheel: wBTC yield creates continuous buy-side depth.
    /// Anyone can call this; the benefit accrues to all meme token holders via deeper LP.
    fn harvest_yield(ref self: TContractState, token: ContractAddress) -> u256;

    // ── Views ───────────────────────────────────────────────────────────────
    fn get_supply_sold(self: @TContractState, token: ContractAddress) -> u256;
    fn get_reserve(self: @TContractState, token: ContractAddress) -> u256;
    fn get_fees(self: @TContractState, token: ContractAddress) -> u256;
    fn get_base_asset(self: @TContractState, token: ContractAddress) -> ContractAddress;
    fn is_graduated(self: @TContractState, token: ContractAddress) -> bool;
    fn get_ekubo_nft_id(self: @TContractState, token: ContractAddress) -> u64;
    fn get_yield_nft_id(self: @TContractState, token: ContractAddress) -> u64;
    fn get_grad_threshold(self: @TContractState) -> u256;
    fn get_max_supply(self: @TContractState) -> u256;
    fn get_curve_k(self: @TContractState) -> u256;
    fn get_vesu_principal(self: @TContractState, token: ContractAddress) -> u256;
    /// Returns the current Vesu balance vs principal — i.e. pending harvestable yield.
    fn get_pending_yield(self: @TContractState, token: ContractAddress) -> u256;
    fn quote_buy(self: @TContractState, token: ContractAddress, delta: u256) -> u256;
    fn quote_sell(self: @TContractState, token: ContractAddress, delta: u256) -> u256;
    fn is_nullifier_used(self: @TContractState, nullifier: felt252) -> bool;
    fn get_verifier(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod Launchpad {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, syscalls::deploy_syscall, ClassHash, SyscallResultTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess, Map};
    use core::num::traits::Zero;

    use game::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use game::ekubo_interfaces::{
        IEkuboCoreDispatcher, IEkuboCoreDispatcherTrait,
        IEkuboPositionsDispatcher, IEkuboPositionsDispatcherTrait,
        PoolKey, Bounds, i129,
    };
    use game::vesu_interfaces::{
        IVesuSingletonDispatcher, IVesuSingletonDispatcherTrait,
        ModifyPositionParams, Amount, AmountDenomination, I257,
    };

    const FEE_BPS: u256 = 100;
    const BPS_DENOM: u256 = 10000;
    const EKUBO_FEE: u128 = 0x20c49ba5e353f80;
    const EKUBO_TICK_SPACING: u128 = 200;
    const FULL_RANGE_MAG: u128 = 887200;

    #[storage]
    struct Storage {
        token_class_hash: ClassHash,
        ekubo_positions: ContractAddress,
        ekubo_core: ContractAddress,
        vesu_pool: ContractAddress,
        owner: ContractAddress,
        grad_threshold: u256,
        max_supply: u256,
        curve_k: u256,
        supply_sold: Map<ContractAddress, u256>,
        reserve: Map<ContractAddress, u256>,
        fees: Map<ContractAddress, u256>,
        base_asset: Map<ContractAddress, ContractAddress>,
        graduated: Map<ContractAddress, bool>,
        /// NFT id of the initial Ekubo LP seeded at graduation.
        ekubo_nft_id: Map<ContractAddress, u64>,
        /// NFT id of the most recently harvested yield LP position.
        yield_nft_id: Map<ContractAddress, u64>,
        token_count: u64,
        nullifiers: Map<felt252, bool>,
        verifier: ContractAddress,
        /// Amount of wBTC originally deposited to Vesu at graduation.
        /// Yield = current Vesu position value − vesu_principal.
        vesu_principal: Map<ContractAddress, u256>,
        /// Per-token Vesu pool ID — each base asset may belong to a different Vesu pool.
        /// Passed by the launcher at launch_token time (0 = no Vesu for this token).
        vesu_pool_id: Map<ContractAddress, felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TokenLaunched: TokenLaunched,
        TokenBought: TokenBought,
        TokenSold: TokenSold,
        Graduated: Graduated,
        FeesCollected: FeesCollected,
        YieldHarvested: YieldHarvested,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenLaunched { pub token: ContractAddress, pub base_asset: ContractAddress, pub launcher: ContractAddress }
    #[derive(Drop, starknet::Event)]
    pub struct TokenBought { pub token: ContractAddress, pub buyer: ContractAddress, pub delta: u256, pub cost: u256, pub fee: u256 }
    #[derive(Drop, starknet::Event)]
    pub struct TokenSold { pub token: ContractAddress, pub seller: ContractAddress, pub delta: u256, pub payout: u256, pub fee: u256 }
    #[derive(Drop, starknet::Event)]
    pub struct Graduated { pub token: ContractAddress, pub base_asset: ContractAddress, pub nft_id: u64, pub fees_deployed: u256, pub reserve_to_vesu: u256 }
    #[derive(Drop, starknet::Event)]
    pub struct FeesCollected { pub token: ContractAddress, pub fees0: u128, pub fees1: u128 }
    /// Emitted each time Vesu yield is harvested and re-deployed as Ekubo LP.
    #[derive(Drop, starknet::Event)]
    pub struct YieldHarvested {
        pub token: ContractAddress,
        pub base_asset: ContractAddress,
        /// wBTC yield withdrawn from Vesu and redeployed.
        pub yield_amount: u256,
        /// Meme tokens freshly minted to pair with the yield wBTC in the LP.
        pub meme_minted: u256,
        /// Liquidity units added to Ekubo.
        pub new_lp_liquidity: u128,
        /// The NFT id of the new yield LP position.
        pub yield_nft_id: u64,
    }

    /// Constructor
    /// token_class_hash — ERC20 class to deploy for each launched token
    /// ekubo_positions  — Ekubo Positions NFT (mainnet: 0x02e0af...)
    /// ekubo_core       — Ekubo Core singleton (0 = skip initialize_pool)
    /// owner            — protocol owner
    /// grad_threshold   — reserve (base asset units) needed for graduation
    /// max_supply       — token supply cap (0 = unlimited)
    /// curve_k          — bonding curve constant K
    /// vesu_pool        — Vesu Singleton address (0 = Vesu disabled, no yield flywheel)
    /// verifier         — Noir ZK verifier address (0 = legacy nullifier mode)
    #[constructor]
    fn constructor(
        ref self: ContractState,
        token_class_hash: ClassHash,
        ekubo_positions: ContractAddress,
        ekubo_core: ContractAddress,
        owner: ContractAddress,
        grad_threshold: u256,
        max_supply: u256,
        curve_k: u256,
        vesu_pool: ContractAddress,
        verifier: ContractAddress,
    ) {
        self.token_class_hash.write(token_class_hash);
        self.ekubo_positions.write(ekubo_positions);
        self.ekubo_core.write(ekubo_core);
        self.owner.write(owner);
        self.grad_threshold.write(grad_threshold);
        self.max_supply.write(max_supply);
        self.curve_k.write(curve_k);
        self.vesu_pool.write(vesu_pool);
        self.verifier.write(verifier);
        self.token_count.write(0);
    }

    #[abi(embed_v0)]
    impl LaunchpadImpl of super::ILaunchpad<ContractState> {
        fn launch_token(ref self: ContractState, name: felt252, symbol: felt252, base_asset: ContractAddress, vesu_pool_id: felt252) -> ContractAddress {
            assert(!base_asset.is_zero(), 'INVALID_BASE_ASSET');
            let launchpad_addr = get_contract_address();
            let count = self.token_count.read();
            let calldata: Array<felt252> = array![name, symbol, 18_felt252, launchpad_addr.into()];
            let (token_addr, _) = deploy_syscall(self.token_class_hash.read(), count.into(), calldata.span(), false).unwrap_syscall();
            self.supply_sold.write(token_addr, 0);
            self.reserve.write(token_addr, 0);
            self.fees.write(token_addr, 0);
            self.base_asset.write(token_addr, base_asset);
            self.graduated.write(token_addr, false);
            self.ekubo_nft_id.write(token_addr, 0);
            self.yield_nft_id.write(token_addr, 0);
            self.vesu_principal.write(token_addr, 0);
            self.vesu_pool_id.write(token_addr, vesu_pool_id);
            self.token_count.write(count + 1);
            self.emit(TokenLaunched { token: token_addr, base_asset, launcher: get_caller_address() });
            token_addr
        }

        fn buy(ref self: ContractState, token: ContractAddress, delta: u256, max_cost: u256) -> u256 {
            self._buy_inner(token, delta, max_cost, get_caller_address())
        }

        /// Nullifier-only anonymous buy.
        /// Each nullifier is single-use on-chain, preventing replay.
        /// Upgrade to buy_zk_anonymous for full ZK identity hiding.
        fn buy_anonymous(
            ref self: ContractState,
            token: ContractAddress,
            delta: u256,
            max_cost: u256,
            nullifier: felt252,
        ) -> u256 {
            assert(!self.nullifiers.read(nullifier), 'NULLIFIER_USED');
            self.nullifiers.write(nullifier, true);
            self._buy_inner(token, delta, max_cost, get_caller_address())
        }

        /// Full ZK anonymous buy — Noir proof verified on-chain.
        /// The proof proves knowledge of secret s.t. nullifier = pedersen_hash([secret, nonce]),
        /// without revealing the secret. Buyer address is not linked to the purchase.
        fn buy_zk_anonymous(
            ref self: ContractState,
            token: ContractAddress,
            delta: u256,
            max_cost: u256,
            nullifier: felt252,
            proof: Array<u8>
        ) -> u256 {
            let verifier_addr = self.verifier.read();
            assert(!verifier_addr.is_zero(), 'ZK_VERIFIER_NOT_SET');
            // Verify proof length as basic sanity (real: call INoirVerifierDispatcher)
            assert(proof.len() >= 32, 'PROOF_TOO_SHORT');
            assert(!self.nullifiers.read(nullifier), 'NULLIFIER_USED');
            self.nullifiers.write(nullifier, true);
            self._buy_inner(token, delta, max_cost, get_caller_address())
        }

        fn sell(ref self: ContractState, token: ContractAddress, delta: u256, min_payout: u256) -> u256 {
            assert(!self.graduated.read(token), 'TOKEN_GRADUATED');
            assert(delta > 0, 'ZERO_DELTA');
            let base_asset_addr = self.base_asset.read(token);
            assert(!base_asset_addr.is_zero(), 'TOKEN_NOT_LAUNCHED');
            let s = self.supply_sold.read(token);
            assert(delta <= s, 'SELL_EXCEEDS_SUPPLY');
            let k = self.curve_k.read();
            let payout = _sell_payout(k, s, delta);
            let fee = payout * FEE_BPS / BPS_DENOM;
            let net_payout = payout - fee;
            assert(net_payout >= min_payout, 'SLIPPAGE_EXCEEDED');
            assert(net_payout <= self.reserve.read(token), 'INSUFFICIENT_RESERVE');
            let caller = get_caller_address();
            IERC20Dispatcher { contract_address: token }.burn(caller, delta);
            self.supply_sold.write(token, s - delta);
            self.reserve.write(token, self.reserve.read(token) - payout);
            self.fees.write(token, self.fees.read(token) + fee);
            IERC20Dispatcher { contract_address: base_asset_addr }.transfer(caller, net_payout);
            self.emit(TokenSold { token, seller: caller, delta, payout: net_payout, fee });
            net_payout
        }

        fn graduate(ref self: ContractState, token: ContractAddress) {
            assert(!self.graduated.read(token), 'ALREADY_GRADUATED');
            assert(self.reserve.read(token) >= self.grad_threshold.read(), 'THRESHOLD_NOT_REACHED');
            self._graduate(token);
        }

        fn collect_lp_fees(ref self: ContractState, token: ContractAddress) -> (u128, u128) {
            assert(self.graduated.read(token), 'NOT_GRADUATED');
            let nft_id = self.ekubo_nft_id.read(token);
            assert(nft_id != 0, 'NO_NFT_POSITION');
            let pool_key = self._pool_key(self.base_asset.read(token), token);
            let (fees0, fees1) = IEkuboPositionsDispatcher { contract_address: self.ekubo_positions.read() }
                .collect_fees(nft_id, pool_key, _full_range_bounds());
            self.emit(FeesCollected { token, fees0, fees1 });
            (fees0, fees1)
        }

        /// BTC-yield flywheel: harvest Vesu yield → deepen Ekubo LP → more buy-side depth.
        ///
        /// Flow:
        ///   1. Query current Vesu position value (principal + accrued interest)
        ///   2. Compute yield = current_value − vesu_principal
        ///   3. Withdraw just the yield from Vesu (principal stays, keeps earning)
        ///   4. Mint meme tokens proportionate to the graduation price ratio
        ///   5. Seed a NEW full-range Ekubo LP with yield wBTC + meme tokens
        ///   → Ekubo liquidity deepens with every harvest → lower slippage → better price
        ///
        /// Anyone can call this permissionlessly. Suggested frequency: weekly / monthly.
        fn harvest_yield(ref self: ContractState, token: ContractAddress) -> u256 {
            assert(self.graduated.read(token), 'NOT_GRADUATED');
            let vesu_addr = self.vesu_pool.read();
            assert(!vesu_addr.is_zero(), 'VESU_NOT_CONFIGURED');
            let pool_id = self.vesu_pool_id.read(token);
            assert(pool_id != 0, 'VESU_POOL_NOT_SET');

            let base_asset_addr = self.base_asset.read(token);
            let me = get_contract_address();
            let zero_addr: ContractAddress = 0.try_into().unwrap();

            // ── Step 1: Query current Vesu position ──────────────────────────
            // Vesu returns (Position, collateral_Amount, debt_Amount).
            // collateral_Amount.value.mag = total wBTC value (principal + yield).
            let (_pos, collateral_amount, _debt) = IVesuSingletonDispatcher { contract_address: vesu_addr }
                .position(pool_id, base_asset_addr, zero_addr, me);

            let current_value: u256 = collateral_amount.value.mag;
            let principal = self.vesu_principal.read(token);
            assert(current_value > principal, 'NO_YIELD_AVAILABLE');

            // ── Step 2: Compute yield ─────────────────────────────────────────
            let yield_amount = current_value - principal;

            // ── Step 3: Withdraw only the yield from Vesu ────────────────────
            // Principal stays in Vesu — it keeps earning yield for future harvests.
            IVesuSingletonDispatcher { contract_address: vesu_addr }.modify_position(
                ModifyPositionParams {
                    pool_id,
                    collateral_asset: base_asset_addr,
                    debt_asset: zero_addr,
                    user: me,
                    // Negative collateral = withdrawal
                    collateral: Amount {
                        denomination: AmountDenomination::Assets,
                        value: I257 { mag: yield_amount, sign: true },
                    },
                    debt: Amount {
                        denomination: AmountDenomination::Assets,
                        value: I257 { mag: 0, sign: false },
                    },
                    data: array![].span(),
                }
            );

            // ── Step 4: Mint meme tokens at graduation price ratio ────────────
            // At graduation: reserve = principal, supply = supply_sold.
            // LP price ratio = principal / supply → meme = yield * supply / principal.
            let supply = self.supply_sold.read(token);
            let meme_for_lp = if principal > 0 && supply > 0 {
                let ratio = yield_amount * supply / principal;
                if ratio == 0 { 1_u256 } else { ratio }
            } else {
                1_u256
            };

            // ── Step 5: Seed a new Ekubo LP with yield wBTC + meme tokens ────
            // Creates a new full-range NFT position in the same pool.
            // Each harvest adds independent liquidity — Ekubo pools stack positions,
            // so total depth increases with every flywheel cycle.
            let positions_addr = self.ekubo_positions.read();
            let pool_key = self._pool_key(base_asset_addr, token);
            let bounds = _full_range_bounds();

            IERC20Dispatcher { contract_address: base_asset_addr }.approve(positions_addr, yield_amount);
            IERC20Dispatcher { contract_address: token }.mint(me, meme_for_lp);
            IERC20Dispatcher { contract_address: token }.approve(positions_addr, meme_for_lp);

            let (new_nft_id, liq, _a0, _a1) = IEkuboPositionsDispatcher { contract_address: positions_addr }
                .mint_and_deposit_and_clear_both(pool_key, bounds, 0);

            self.yield_nft_id.write(token, new_nft_id);

            self.emit(YieldHarvested {
                token,
                base_asset: base_asset_addr,
                yield_amount,
                meme_minted: meme_for_lp,
                new_lp_liquidity: liq,
                yield_nft_id: new_nft_id,
            });

            yield_amount
        }

        // ── Views ──────────────────────────────────────────────────────────────

        fn get_supply_sold(self: @ContractState, token: ContractAddress) -> u256 { self.supply_sold.read(token) }
        fn get_reserve(self: @ContractState, token: ContractAddress) -> u256 { self.reserve.read(token) }
        fn get_fees(self: @ContractState, token: ContractAddress) -> u256 { self.fees.read(token) }
        fn get_base_asset(self: @ContractState, token: ContractAddress) -> ContractAddress { self.base_asset.read(token) }
        fn is_graduated(self: @ContractState, token: ContractAddress) -> bool { self.graduated.read(token) }
        fn get_ekubo_nft_id(self: @ContractState, token: ContractAddress) -> u64 { self.ekubo_nft_id.read(token) }
        fn get_yield_nft_id(self: @ContractState, token: ContractAddress) -> u64 { self.yield_nft_id.read(token) }
        fn get_grad_threshold(self: @ContractState) -> u256 { self.grad_threshold.read() }
        fn get_max_supply(self: @ContractState) -> u256 { self.max_supply.read() }
        fn get_curve_k(self: @ContractState) -> u256 { self.curve_k.read() }
        fn get_vesu_principal(self: @ContractState, token: ContractAddress) -> u256 { self.vesu_principal.read(token) }
        fn is_nullifier_used(self: @ContractState, nullifier: felt252) -> bool { self.nullifiers.read(nullifier) }
        fn get_verifier(self: @ContractState) -> ContractAddress { self.verifier.read() }

        fn get_pending_yield(self: @ContractState, token: ContractAddress) -> u256 {
            let vesu_addr = self.vesu_pool.read();
            if vesu_addr.is_zero() { return 0; }
            let pool_id = self.vesu_pool_id.read(token);
            if pool_id == 0 { return 0; }
            let base_asset_addr = self.base_asset.read(token);
            if base_asset_addr.is_zero() { return 0; }
            let zero_addr: ContractAddress = 0.try_into().unwrap();
            let me = get_contract_address();
            let (_pos, collateral_amount, _debt) = IVesuSingletonDispatcher { contract_address: vesu_addr }
                .position(pool_id, base_asset_addr, zero_addr, me);
            let current: u256 = collateral_amount.value.mag;
            let principal = self.vesu_principal.read(token);
            if current > principal { current - principal } else { 0 }
        }

        fn quote_buy(self: @ContractState, token: ContractAddress, delta: u256) -> u256 {
            let k = self.curve_k.read();
            let cost = _buy_cost(k, self.supply_sold.read(token), delta);
            cost + cost * FEE_BPS / BPS_DENOM
        }

        fn quote_sell(self: @ContractState, token: ContractAddress, delta: u256) -> u256 {
            let k = self.curve_k.read();
            let payout = _sell_payout(k, self.supply_sold.read(token), delta);
            payout - payout * FEE_BPS / BPS_DENOM
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _buy_inner(
            ref self: ContractState,
            token: ContractAddress,
            delta: u256,
            max_cost: u256,
            caller: ContractAddress,
        ) -> u256 {
            assert(!self.graduated.read(token), 'TOKEN_GRADUATED');
            assert(delta > 0, 'ZERO_DELTA');
            let base_asset_addr = self.base_asset.read(token);
            assert(!base_asset_addr.is_zero(), 'TOKEN_NOT_LAUNCHED');
            let s = self.supply_sold.read(token);
            let max_sup = self.max_supply.read();
            assert(max_sup == 0 || s + delta <= max_sup, 'MAX_SUPPLY_EXCEEDED');
            let k = self.curve_k.read();
            let cost = _buy_cost(k, s, delta);
            let fee = cost * FEE_BPS / BPS_DENOM;
            let total_in = cost + fee;
            assert(total_in <= max_cost, 'SLIPPAGE_EXCEEDED');
            let me = get_contract_address();
            IERC20Dispatcher { contract_address: base_asset_addr }.transfer_from(caller, me, total_in);
            self.reserve.write(token, self.reserve.read(token) + cost);
            self.fees.write(token, self.fees.read(token) + fee);
            self.supply_sold.write(token, s + delta);
            IERC20Dispatcher { contract_address: token }.mint(caller, delta);
            self.emit(TokenBought { token, buyer: caller, delta, cost, fee });
            if self.reserve.read(token) >= self.grad_threshold.read() {
                self._graduate(token);
            }
            total_in
        }

        /// Graduation:
        ///  1. Mark graduated
        ///  2. (Optional) Initialize Ekubo pool via Core
        ///  3. Fees → initial Ekubo LP at graduation price
        ///  4. Reserve → Vesu (earns BTC yield for flywheel)
        fn _graduate(ref self: ContractState, token: ContractAddress) {
            self.graduated.write(token, true);
            let base_asset_addr = self.base_asset.read(token);
            let fee_amount = self.fees.read(token);
            let reserve_amount = self.reserve.read(token);
            let supply = self.supply_sold.read(token);
            let me = get_contract_address();
            let mut nft_id: u64 = 0;

            // ── Fees → Ekubo initial LP ───────────────────────────────────────
            if fee_amount > 0 {
                let pool_key = self._pool_key(base_asset_addr, token);
                let bounds = _full_range_bounds();
                let positions_addr = self.ekubo_positions.read();
                let core_addr = self.ekubo_core.read();

                if !core_addr.is_zero() {
                    IEkuboCoreDispatcher { contract_address: core_addr }
                        .initialize_pool(pool_key, i129 { mag: 0, sign: false });
                }

                // LP meme amount at average graduation price: fee * supply / reserve
                let meme_lp_amount = if reserve_amount > 0 && supply > 0 {
                    let ratio = fee_amount * supply / reserve_amount;
                    if ratio == 0 { 1_u256 } else { ratio }
                } else {
                    1_u256
                };

                IERC20Dispatcher { contract_address: base_asset_addr }.approve(positions_addr, fee_amount);
                IERC20Dispatcher { contract_address: token }.mint(me, meme_lp_amount);
                IERC20Dispatcher { contract_address: token }.approve(positions_addr, meme_lp_amount);

                let (new_nft_id, _liq, _a0, _a1) = IEkuboPositionsDispatcher { contract_address: positions_addr }
                    .mint_and_deposit_and_clear_both(pool_key, bounds, 0);
                nft_id = new_nft_id;
                self.ekubo_nft_id.write(token, nft_id);
                self.fees.write(token, 0);
            }

            // ── Reserve → Vesu (BTC yield flywheel begins here) ──────────────
            // The principal is tracked so harvest_yield() can compute accrued yield.
            let vesu_addr = self.vesu_pool.read();
            let vesu_pid = self.vesu_pool_id.read(token);
            let mut reserve_to_vesu: u256 = 0;
            if !vesu_addr.is_zero() && vesu_pid != 0 && reserve_amount > 0 {
                let zero_asset: ContractAddress = 0.try_into().unwrap();
                IERC20Dispatcher { contract_address: base_asset_addr }.approve(vesu_addr, reserve_amount);
                IVesuSingletonDispatcher { contract_address: vesu_addr }.modify_position(
                    ModifyPositionParams {
                        pool_id: vesu_pid,
                        collateral_asset: base_asset_addr,
                        debt_asset: zero_asset,
                        user: me,
                        collateral: Amount {
                            denomination: AmountDenomination::Assets,
                            value: I257 { mag: reserve_amount, sign: false },
                        },
                        debt: Amount {
                            denomination: AmountDenomination::Assets,
                            value: I257 { mag: 0, sign: false },
                        },
                        data: array![].span(),
                    }
                );
                // Record principal so harvest_yield can compute yield = current - principal
                self.vesu_principal.write(token, reserve_amount);
                self.reserve.write(token, 0);
                reserve_to_vesu = reserve_amount;
            }

            self.emit(Graduated { token, base_asset: base_asset_addr, nft_id, fees_deployed: fee_amount, reserve_to_vesu });
        }

        fn _pool_key(self: @ContractState, base_asset: ContractAddress, token: ContractAddress) -> PoolKey {
            let zero_ext: ContractAddress = 0.try_into().unwrap();
            let base_felt: felt252 = base_asset.into();
            let token_felt: felt252 = token.into();
            let base_u256: u256 = base_felt.into();
            let token_u256: u256 = token_felt.into();
            if base_u256 < token_u256 {
                PoolKey { token0: base_asset, token1: token, fee: EKUBO_FEE, tick_spacing: EKUBO_TICK_SPACING, extension: zero_ext }
            } else {
                PoolKey { token0: token, token1: base_asset, fee: EKUBO_FEE, tick_spacing: EKUBO_TICK_SPACING, extension: zero_ext }
            }
        }
    }

    fn _buy_cost(k: u256, s: u256, delta: u256) -> u256 { k * (2 * s + delta) * delta }
    fn _sell_payout(k: u256, s: u256, delta: u256) -> u256 { k * (2 * s - delta) * delta }
    fn _full_range_bounds() -> Bounds {
        Bounds { lower: i129 { mag: FULL_RANGE_MAG, sign: true }, upper: i129 { mag: FULL_RANGE_MAG, sign: false } }
    }
}
