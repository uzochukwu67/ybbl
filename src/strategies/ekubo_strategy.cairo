use starknet::ContractAddress;

// ============================================================================
// Ekubo LP Strategy
// Deploys vault funds as liquidity into Ekubo DEX pools to earn swap fees.
// Manages a single-sided deposit approach: deposits the vault's token
// alongside a paired token into an Ekubo concentrated liquidity pool.
// ============================================================================

#[starknet::contract]
mod EkuboStrategy {
    use core::traits::Into;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::info::get_block_timestamp;

    use reddio_cairo::interfaces::IERC20Dispatcher;
    use reddio_cairo::interfaces::IERC20DispatcherTrait;
    use reddio_cairo::interfaces::IEkuboRouterDispatcher;
    use reddio_cairo::interfaces::IEkuboRouterDispatcherTrait;

    // ========================================================================
    // Storage
    // ========================================================================

    #[storage]
    struct Storage {
        // The vault that owns this strategy
        vault: ContractAddress,
        // The curator who can manage the strategy
        curator: ContractAddress,
        // The Ekubo router/position manager contract
        ekubo_router: ContractAddress,
        // Primary deposit token (from vault, e.g., WBTC)
        token_a: ContractAddress,
        // Paired token for the LP pool (e.g., ETH or USDC)
        token_b: ContractAddress,
        // Amount of token_a principal deposited as liquidity
        principal_deposited: u256,
        // Total liquidity tokens held
        liquidity_held: u256,
        // Total yield harvested historically
        total_yield_harvested: u256,
        // Whether the strategy is initialized
        initialized: bool,
        // Whether the strategy is paused
        paused: bool,
    }

    // ========================================================================
    // Events
    // ========================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        LiquidityAdded: LiquidityAdded,
        LiquidityRemoved: LiquidityRemoved,
        FeesHarvested: FeesHarvested,
        EmergencyWithdrawn: EmergencyWithdrawn,
    }

    #[derive(Drop, starknet::Event)]
    struct LiquidityAdded {
        amount_a: u256,
        amount_b: u256,
        liquidity: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct LiquidityRemoved {
        liquidity: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct FeesHarvested {
        yield_amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyWithdrawn {
        amount: u256,
        timestamp: u64,
    }

    // ========================================================================
    // Initialization
    // ========================================================================

    #[starknet::interface]
    trait IEkuboStrategyInit<TContractState> {
        fn initialize(
            ref self: TContractState,
            vault: ContractAddress,
            curator: ContractAddress,
            ekubo_router: ContractAddress,
            token_a: ContractAddress,
            token_b: ContractAddress,
        );
    }

    #[abi(embed_v0)]
    impl EkuboStrategyInitImpl of IEkuboStrategyInit<ContractState> {
        fn initialize(
            ref self: ContractState,
            vault: ContractAddress,
            curator: ContractAddress,
            ekubo_router: ContractAddress,
            token_a: ContractAddress,
            token_b: ContractAddress,
        ) {
            assert(!self.initialized.read(), 'Already initialized');
            assert(vault != contract_address_const::<0>(), 'Invalid vault');
            assert(curator != contract_address_const::<0>(), 'Invalid curator');
            assert(ekubo_router != contract_address_const::<0>(), 'Invalid router');
            assert(token_a != contract_address_const::<0>(), 'Invalid token_a');
            assert(token_b != contract_address_const::<0>(), 'Invalid token_b');

            self.initialized.write(true);
            self.vault.write(vault);
            self.curator.write(curator);
            self.ekubo_router.write(ekubo_router);
            self.token_a.write(token_a);
            self.token_b.write(token_b);
            self.paused.write(false);
        }
    }

    // ========================================================================
    // Strategy Adapter Implementation
    // ========================================================================

    #[abi(embed_v0)]
    impl StrategyAdapterImpl of reddio_cairo::interfaces::IStrategyAdapter<ContractState> {
        // ----------------------------------------------------------------
        // Deposit: Add liquidity to Ekubo pool
        // The vault sends token_a; we pair it with token_b for the LP
        // For simplicity, we do equal-value deposits
        // ----------------------------------------------------------------
        fn deposit(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            self._assert_not_paused();
            assert(amount > 0, 'Amount must be > 0');

            let token_a_dispatcher = IERC20Dispatcher {
                contract_address: self.token_a.read(),
            };
            let token_b_dispatcher = IERC20Dispatcher {
                contract_address: self.token_b.read(),
            };
            let this = get_contract_address();

            // Verify we have enough token_a
            let balance_a = token_a_dispatcher.balance_of(this);
            assert(balance_a >= amount, 'Insufficient token_a');

            // For LP: use matching amount of token_b
            // In production, would use oracle for price-matched amounts
            let amount_b = token_b_dispatcher.balance_of(this);

            let router_addr = self.ekubo_router.read();

            // Approve router to spend both tokens
            token_a_dispatcher.approve(router_addr, amount);
            if amount_b > 0 {
                token_b_dispatcher.approve(router_addr, amount_b);
            }

            // Add liquidity to Ekubo
            let router = IEkuboRouterDispatcher { contract_address: router_addr };
            let liquidity = router
                .add_liquidity(
                    self.token_a.read(),
                    self.token_b.read(),
                    amount,
                    amount_b,
                    0, // min_liquidity = 0 for MVP
                );

            // Update accounting
            self.principal_deposited.write(self.principal_deposited.read() + amount);
            self.liquidity_held.write(self.liquidity_held.read() + liquidity);

            self
                .emit(
                    Event::LiquidityAdded(
                        LiquidityAdded {
                            amount_a: amount,
                            amount_b,
                            liquidity,
                            timestamp: get_block_timestamp(),
                        }
                    )
                );
        }

        // ----------------------------------------------------------------
        // Withdraw: Remove liquidity from Ekubo and return tokens to vault
        // ----------------------------------------------------------------
        fn withdraw(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            assert(amount > 0, 'Amount must be > 0');

            let total_balance = self._get_position_value();
            assert(amount <= total_balance, 'Exceeds position value');

            // Calculate proportional liquidity to remove
            let total_liq = self.liquidity_held.read();
            let liq_to_remove = if total_balance > 0 {
                (total_liq * amount) / total_balance
            } else {
                0
            };

            if liq_to_remove == 0 {
                return;
            }

            let router = IEkuboRouterDispatcher { contract_address: self.ekubo_router.read() };
            let token_a_dispatcher = IERC20Dispatcher {
                contract_address: self.token_a.read(),
            };
            let this = get_contract_address();

            let balance_before = token_a_dispatcher.balance_of(this);

            // Remove liquidity
            router
                .remove_liquidity(
                    self.token_a.read(),
                    self.token_b.read(),
                    liq_to_remove,
                    0, // min_amount_a
                    0, // min_amount_b
                );

            let balance_after = token_a_dispatcher.balance_of(this);
            let recovered_a = balance_after - balance_before;

            // Send token_a back to vault
            token_a_dispatcher.transfer(self.vault.read(), recovered_a);

            // Update accounting
            self.liquidity_held.write(total_liq - liq_to_remove);
            let principal = self.principal_deposited.read();
            if recovered_a <= principal {
                self.principal_deposited.write(principal - recovered_a);
            } else {
                self.principal_deposited.write(0);
            }

            self
                .emit(
                    Event::LiquidityRemoved(
                        LiquidityRemoved {
                            liquidity: liq_to_remove, timestamp: get_block_timestamp(),
                        }
                    )
                );
        }

        // ----------------------------------------------------------------
        // Harvest: Collect accumulated swap fees
        // ----------------------------------------------------------------
        fn harvest(ref self: ContractState) -> u256 {
            self._only_vault_or_curator();
            self._assert_not_paused();

            let total_value = self._get_position_value();
            let principal = self.principal_deposited.read();

            if total_value <= principal {
                return 0;
            }

            let yield_amount = total_value - principal;

            // Remove just the yield portion as liquidity
            let total_liq = self.liquidity_held.read();
            let liq_for_yield = if total_value > 0 {
                (total_liq * yield_amount) / total_value
            } else {
                0
            };

            if liq_for_yield == 0 {
                return 0;
            }

            let router = IEkuboRouterDispatcher { contract_address: self.ekubo_router.read() };
            let token_a_dispatcher = IERC20Dispatcher {
                contract_address: self.token_a.read(),
            };
            let this = get_contract_address();

            let balance_before = token_a_dispatcher.balance_of(this);

            router
                .remove_liquidity(
                    self.token_a.read(), self.token_b.read(), liq_for_yield, 0, 0,
                );

            let balance_after = token_a_dispatcher.balance_of(this);
            let harvested = balance_after - balance_before;

            // Send harvested yield to vault
            token_a_dispatcher.transfer(self.vault.read(), harvested);

            // Update accounting
            self.liquidity_held.write(total_liq - liq_for_yield);
            self.total_yield_harvested.write(self.total_yield_harvested.read() + harvested);

            self
                .emit(
                    Event::FeesHarvested(
                        FeesHarvested { yield_amount: harvested, timestamp: get_block_timestamp() }
                    )
                );

            harvested
        }

        fn get_total_balance(self: @ContractState) -> u256 {
            self._get_position_value()
        }

        fn get_pending_yield(self: @ContractState) -> u256 {
            let total = self._get_position_value();
            let principal = self.principal_deposited.read();
            if total > principal {
                total - principal
            } else {
                0
            }
        }

        fn get_protocol(self: @ContractState) -> ContractAddress {
            self.ekubo_router.read()
        }

        fn get_vault(self: @ContractState) -> ContractAddress {
            self.vault.read()
        }

        // ----------------------------------------------------------------
        // Emergency: Remove all liquidity and return to vault
        // ----------------------------------------------------------------
        fn emergency_withdraw(ref self: ContractState) -> u256 {
            self._only_curator();

            let total_liq = self.liquidity_held.read();
            if total_liq == 0 {
                return 0;
            }

            let router = IEkuboRouterDispatcher { contract_address: self.ekubo_router.read() };
            let token_a_dispatcher = IERC20Dispatcher {
                contract_address: self.token_a.read(),
            };
            let this = get_contract_address();

            let balance_before = token_a_dispatcher.balance_of(this);

            router
                .remove_liquidity(self.token_a.read(), self.token_b.read(), total_liq, 0, 0);

            let balance_after = token_a_dispatcher.balance_of(this);
            let recovered = balance_after - balance_before;

            // Send everything to vault
            token_a_dispatcher.transfer(self.vault.read(), recovered);

            // Reset accounting
            self.liquidity_held.write(0);
            self.principal_deposited.write(0);
            self.paused.write(true);

            self
                .emit(
                    Event::EmergencyWithdrawn(
                        EmergencyWithdrawn { amount: recovered, timestamp: get_block_timestamp() }
                    )
                );

            recovered
        }
    }

    // ========================================================================
    // Internal Functions
    // ========================================================================

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _only_vault_or_curator(self: @ContractState) {
            let caller = get_caller_address();
            assert(
                caller == self.vault.read() || caller == self.curator.read(),
                'Only vault or curator',
            );
        }

        fn _only_curator(self: @ContractState) {
            assert(get_caller_address() == self.curator.read(), 'Only curator');
        }

        fn _assert_not_paused(self: @ContractState) {
            assert(!self.paused.read(), 'Strategy paused');
        }

        fn _get_position_value(self: @ContractState) -> u256 {
            let router = IEkuboRouterDispatcher { contract_address: self.ekubo_router.read() };
            router.get_position_value(self.token_a.read(), self.token_b.read(), get_contract_address())
        }
    }
}
