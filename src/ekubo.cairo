/// Ekubo LP Strategy — concentrated liquidity management
/// Core Domain: deposit/withdraw liquidity, collect fees
///
/// Implements IStrategy (common vault interface) + IEkuboLPStrategyExt (protocol-specific).
/// Uses vendored Ekubo interfaces from src/interfaces/ekubo.cairo.

#[starknet::contract]
pub mod EkuboLPStrategy {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    // Ekubo vendored types
    use super::super::super::interfaces::ekubo::{
        IEkuboPositionsDispatcher, IEkuboPositionsDispatcherTrait,
        PoolKey, Bounds, i129, GetTokenInfoResult,
    };

    // ── Component wiring ──
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // ── Events ──
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        FeesCollected: FeesCollected,
        BoundsUpdated: BoundsUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Deposited {
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Withdrawn {
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FeesCollected {
        pub fees0: u128,
        pub fees1: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BoundsUpdated {
        pub lower_mag: u128,
        pub lower_sign: bool,
        pub upper_mag: u128,
        pub upper_sign: bool,
    }

    // ── Storage ──
    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        vault_addr: ContractAddress,
        manager_addr: ContractAddress,
        ekubo_positions: ContractAddress,
        ekubo_core: ContractAddress,
        token0: ContractAddress,          // wBTC
        token1: ContractAddress,          // USDC
        pool_fee: u128,
        pool_tick_spacing: u128,
        pool_extension: ContractAddress,
        nft_id: u64,
        lower_bound: i129,
        upper_bound: i129,
    }

    // ── Constructor ──
    #[constructor]
    fn constructor(
        ref self: ContractState,
        vault: ContractAddress,
        manager: ContractAddress,
        owner: ContractAddress,
        ekubo_positions: ContractAddress,
        ekubo_core: ContractAddress,
        token0: ContractAddress,
        token1: ContractAddress,
        pool_fee: u128,
        pool_tick_spacing: u128,
        pool_extension: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.vault_addr.write(vault);
        self.manager_addr.write(manager);
        self.ekubo_positions.write(ekubo_positions);
        self.ekubo_core.write(ekubo_core);
        self.token0.write(token0);
        self.token1.write(token1);
        self.pool_fee.write(pool_fee);
        self.pool_tick_spacing.write(pool_tick_spacing);
        self.pool_extension.write(pool_extension);
        self.nft_id.write(0);
        self.lower_bound.write(i129 { mag: 0, sign: false });
        self.upper_bound.write(i129 { mag: 0, sign: false });
    }

    // ── IStrategy Implementation ──
    #[abi(embed_v0)]
    impl StrategyImpl of super::super::traits::IStrategy<ContractState> {
        /// Deploy assets (wBTC amount) into Ekubo LP position.
        /// For simplicity, deposits token0 (wBTC) only; the Positions
        /// contract handles single-sided deposit to concentrated range.
        fn deposit(ref self: ContractState, amount: u256) {
            self._assert_vault_or_manager();
            assert(amount > 0, 'ZERO_AMOUNT');

            let token0_addr = self.token0.read();
            let positions_addr = self.ekubo_positions.read();
            let token0_disp = IERC20Dispatcher { contract_address: token0_addr };

            // Strategy must already hold the funds (caller transfers before calling deposit)
            let bal = token0_disp.balance_of(get_contract_address());
            assert(bal >= amount, 'INSUFFICIENT_STRATEGY_BALANCE');

            // Approve Positions contract to spend token0
            token0_disp.approve(positions_addr, amount);

            let pool_key = self._pool_key();
            let bounds = self._bounds();
            let positions_disp = IEkuboPositionsDispatcher { contract_address: positions_addr };

            let current_nft = self.nft_id.read();
            if current_nft == 0 {
                // First deposit — mint NFT
                let (new_nft_id, _liquidity) = positions_disp
                    .mint_and_deposit(pool_key, bounds, 0); // min_liquidity = 0
                self.nft_id.write(new_nft_id);
            } else {
                // Subsequent deposits — add to existing NFT
                positions_disp.deposit(current_nft, pool_key, bounds, 0);
            }

            self.emit(Deposited { amount });
        }

        /// Withdraw wBTC (token0) from Ekubo LP position.
        ///
        /// Calculates proportional liquidity based on token0 (wBTC) only —
        /// NOT the mixed token0+token1 sum (they are different denominations).
        /// If `amount` exceeds available token0, withdraws all liquidity.
        fn withdraw(ref self: ContractState, amount: u256) {
            self._assert_vault_or_manager();
            assert(amount > 0, 'ZERO_AMOUNT');

            let current_nft = self.nft_id.read();
            assert(current_nft != 0, 'NO_POSITION');

            let positions_disp = IEkuboPositionsDispatcher {
                contract_address: self.ekubo_positions.read(),
            };
            let pool_key = self._pool_key();
            let bounds = self._bounds();

            let info: GetTokenInfoResult = positions_disp
                .get_token_info(current_nft, pool_key, bounds);

            let liq: u256 = info.liquidity.into();
            assert(liq > 0, 'EMPTY_POSITION');

            // Calculate liquidity to remove based on token0 (wBTC) ratio only.
            // amount is in wBTC units, so compare against token0 in the position.
            let token0_in_position: u256 = info.amount0.into();
            let liq_to_remove: u128 = if token0_in_position == 0 || amount >= token0_in_position {
                // Position is fully token1 or requesting all token0 → remove all liquidity
                info.liquidity
            } else {
                // Proportional: liquidity * amount / token0_in_position
                let liq_to_remove_256: u256 = (liq * amount) / token0_in_position;
                if liq_to_remove_256 > liq {
                    info.liquidity
                } else {
                    liq_to_remove_256.try_into().unwrap()
                }
            };

            let (_amount0, _amount1) = positions_disp
                .withdraw(current_nft, pool_key, bounds, liq_to_remove, 0, 0, true);

            // Clear nft_id if all liquidity was removed, so set_bounds is unblocked
            if liq_to_remove == info.liquidity {
                self.nft_id.write(0);
            }

            // Transfer only token0 (wBTC) back to vault.
            // token1 (USDC) stays in strategy — vault is wBTC-only and cannot
            // account for USDC. Retained token1 can be swapped or redeployed
            // via a separate keeper/governance path.
            let vault = self.vault_addr.read();
            let token0_disp = IERC20Dispatcher { contract_address: self.token0.read() };
            let bal0 = token0_disp.balance_of(get_contract_address());
            if bal0 > 0 {
                let success = token0_disp.transfer(vault, bal0);
                assert(success, 'WITHDRAW_TRANSFER_FAILED');
            }

            self.emit(Withdrawn { amount });
        }

        /// Total assets denominated in the vault's asset (wBTC = token0).
        /// Only returns token0 position + token0 fees + any free token0 balance
        /// held by this strategy contract (e.g. retained after withdraw).
        /// token1 (USDC) is NOT included because the vault is wBTC-only —
        /// including it would inflate the accounting and cause the Manager to
        /// attempt withdrawing more wBTC than actually exists.
        /// Use `underlying_balance()` and `pending_fees()` to see all tokens.
        fn total_assets(self: @ContractState) -> u256 {
            let current_nft = self.nft_id.read();
            let token0_disp = IERC20Dispatcher {
                contract_address: self.token0.read(),
            };
            // Free wBTC sitting in strategy (retained from partial withdraws etc.)
            let free_balance: u256 = token0_disp.balance_of(get_contract_address());

            if current_nft == 0 {
                return free_balance;
            }

            let positions_disp = IEkuboPositionsDispatcher {
                contract_address: self.ekubo_positions.read(),
            };
            let pool_key = self._pool_key();
            let bounds = self._bounds();
            let info: GetTokenInfoResult = positions_disp
                .get_token_info(current_nft, pool_key, bounds);

            // token0 in position + token0 fees + free token0 balance
            let total: u256 = info.amount0.into()
                + info.fees0.into()
                + free_balance;
            total
        }

        fn vault(self: @ContractState) -> ContractAddress {
            self.vault_addr.read()
        }
    }

    // ── IEkuboLPStrategyExt Implementation ──
    #[abi(embed_v0)]
    impl EkuboLPStrategyExtImpl of super::super::traits::IEkuboLPStrategyExt<ContractState> {
        fn deposit_liquidity(ref self: ContractState, amount0: u256, amount1: u256) {
            self._assert_vault_or_manager();
            let positions_addr = self.ekubo_positions.read();

            // Approve both tokens
            let token0_disp = IERC20Dispatcher { contract_address: self.token0.read() };
            let token1_disp = IERC20Dispatcher { contract_address: self.token1.read() };
            token0_disp.approve(positions_addr, amount0);
            token1_disp.approve(positions_addr, amount1);

            let pool_key = self._pool_key();
            let bounds = self._bounds();
            let positions_disp = IEkuboPositionsDispatcher { contract_address: positions_addr };

            let current_nft = self.nft_id.read();
            if current_nft == 0 {
                let (new_nft_id, _liq) = positions_disp
                    .mint_and_deposit(pool_key, bounds, 0);
                self.nft_id.write(new_nft_id);
            } else {
                positions_disp.deposit(current_nft, pool_key, bounds, 0);
            }
        }

        fn withdraw_liquidity(
            ref self: ContractState, ratio_wad: u256, min_token0: u128, min_token1: u128,
        ) {
            self._assert_vault_or_manager();
            let current_nft = self.nft_id.read();
            assert(current_nft != 0, 'NO_POSITION');

            let positions_disp = IEkuboPositionsDispatcher {
                contract_address: self.ekubo_positions.read(),
            };
            let pool_key = self._pool_key();
            let bounds = self._bounds();

            let info = positions_disp.get_token_info(current_nft, pool_key, bounds);
            // ratio_wad: 1e18 = 100%
            let liq: u256 = info.liquidity.into();
            let liq_to_remove_256: u256 = (liq * ratio_wad) / 1000000000000000000; // 1e18
            let liq_to_remove: u128 = liq_to_remove_256.try_into().unwrap();

            positions_disp
                .withdraw(current_nft, pool_key, bounds, liq_to_remove, min_token0, min_token1, true);

            // Clear nft_id if all liquidity was removed, so set_bounds is unblocked
            if liq_to_remove == info.liquidity {
                self.nft_id.write(0);
            }

            // Transfer only token0 (wBTC) to vault; retain token1 (USDC) in strategy
            let vault = self.vault_addr.read();
            let token0_disp = IERC20Dispatcher { contract_address: self.token0.read() };
            let bal0 = token0_disp.balance_of(get_contract_address());
            if bal0 > 0 {
                let success = token0_disp.transfer(vault, bal0);
                assert(success, 'LIQ_TRANSFER_FAILED');
            }
        }

        fn collect_fees(ref self: ContractState) -> (u128, u128) {
            self._assert_vault_or_manager();
            let current_nft = self.nft_id.read();
            assert(current_nft != 0, 'NO_POSITION');

            let positions_disp = IEkuboPositionsDispatcher {
                contract_address: self.ekubo_positions.read(),
            };
            let pool_key = self._pool_key();
            let bounds = self._bounds();

            let (fees0, fees1) = positions_disp.collect_fees(current_nft, pool_key, bounds);

            // Transfer only token0 (wBTC) fees to vault.
            // token1 (USDC) fees stay in strategy — vault is wBTC-only and
            // cannot account for USDC. Retained token1 can be swept via
            // a separate keeper/governance path.
            let vault = self.vault_addr.read();
            if fees0 > 0 {
                let token0_disp = IERC20Dispatcher { contract_address: self.token0.read() };
                let success = token0_disp.transfer(vault, fees0.into());
                assert(success, 'FEE0_TRANSFER_FAILED');
            }
            // token1 fees intentionally retained in strategy

            self.emit(FeesCollected { fees0, fees1 });
            (fees0, fees1)
        }

        fn set_bounds(
            ref self: ContractState,
            lower_mag: u128, lower_sign: bool,
            upper_mag: u128, upper_sign: bool,
        ) {
            self.ownable.assert_only_owner();
            // Only allow bound changes when no active position
            assert(self.nft_id.read() == 0, 'POSITION_ACTIVE');

            self.lower_bound.write(i129 { mag: lower_mag, sign: lower_sign });
            self.upper_bound.write(i129 { mag: upper_mag, sign: upper_sign });

            self.emit(BoundsUpdated { lower_mag, lower_sign, upper_mag, upper_sign });
        }

        fn get_deposit_ratio(self: @ContractState) -> (u256, u256) {
            // TODO: Calculate based on current price and tick bounds
            // For now return 1:1 placeholder
            (1, 1)
        }

        fn underlying_balance(self: @ContractState) -> (u256, u256) {
            let current_nft = self.nft_id.read();
            if current_nft == 0 {
                return (0, 0);
            }
            let positions_disp = IEkuboPositionsDispatcher {
                contract_address: self.ekubo_positions.read(),
            };
            let info = positions_disp
                .get_token_info(current_nft, self._pool_key(), self._bounds());
            (info.amount0.into(), info.amount1.into())
        }

        fn pending_fees(self: @ContractState) -> (u256, u256) {
            let current_nft = self.nft_id.read();
            if current_nft == 0 {
                return (0, 0);
            }
            let positions_disp = IEkuboPositionsDispatcher {
                contract_address: self.ekubo_positions.read(),
            };
            let info = positions_disp
                .get_token_info(current_nft, self._pool_key(), self._bounds());
            (info.fees0.into(), info.fees1.into())
        }

        fn total_liquidity(self: @ContractState) -> u128 {
            let current_nft = self.nft_id.read();
            if current_nft == 0 {
                return 0;
            }
            let positions_disp = IEkuboPositionsDispatcher {
                contract_address: self.ekubo_positions.read(),
            };
            let info = positions_disp
                .get_token_info(current_nft, self._pool_key(), self._bounds());
            info.liquidity
        }

        fn nft_id(self: @ContractState) -> u64 {
            self.nft_id.read()
        }

        fn set_manager(ref self: ContractState, new_manager: ContractAddress) {
            self.ownable.assert_only_owner();
            self.manager_addr.write(new_manager);
        }

        fn sweep_token1(ref self: ContractState, to: ContractAddress) -> u256 {
            self.ownable.assert_only_owner();
            let token1_disp = IERC20Dispatcher { contract_address: self.token1.read() };
            let bal = token1_disp.balance_of(get_contract_address());
            if bal > 0 {
                let success = token1_disp.transfer(to, bal);
                assert(success, 'SWEEP_TRANSFER_FAILED');
            }
            bal
        }
    }

    // ── Internal Helpers ──
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _pool_key(self: @ContractState) -> PoolKey {
            PoolKey {
                token0: self.token0.read(),
                token1: self.token1.read(),
                fee: self.pool_fee.read(),
                tick_spacing: self.pool_tick_spacing.read(),
                extension: self.pool_extension.read(),
            }
        }

        fn _bounds(self: @ContractState) -> Bounds {
            Bounds {
                lower: self.lower_bound.read(),
                upper: self.upper_bound.read(),
            }
        }

        fn _assert_vault_or_manager(self: @ContractState) {
            let caller = get_caller_address();
            let vault = self.vault_addr.read();
            let manager = self.manager_addr.read();
            assert(caller == vault || caller == manager, 'ONLY_VAULT_OR_MANAGER');
        }
    }
}