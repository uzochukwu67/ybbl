use starknet::ContractAddress;

// ============================================================================
// Strategy Manager
// Orchestrates the three yield strategies (Vesu, Ekubo, Nostra) for the
// Privacy Yield Vault. Handles allocation, rebalancing, yield harvesting,
// and provides a unified view of all deployed capital.
//
// Strategy IDs:
//   0 = Vesu Lending (conservative - lending yield)
//   1 = Ekubo LP (moderate - swap fee yield)
//   2 = Nostra Lending (conservative - lending yield)
// ============================================================================

#[starknet::interface]
trait IStrategyManager<TContractState> {
    // --- Initialization ---
    fn initialize(
        ref self: TContractState,
        vault: ContractAddress,
        curator: ContractAddress,
        deposit_token: ContractAddress,
        vesu_adapter: ContractAddress,
        ekubo_adapter: ContractAddress,
        nostra_adapter: ContractAddress,
    );

    // --- Capital Deployment ---
    fn deploy_to_vesu(ref self: TContractState, amount: u256);
    fn deploy_to_ekubo(ref self: TContractState, amount: u256);
    fn deploy_to_nostra(ref self: TContractState, amount: u256);

    // --- Capital Withdrawal ---
    fn withdraw_from_vesu(ref self: TContractState, amount: u256);
    fn withdraw_from_ekubo(ref self: TContractState, amount: u256);
    fn withdraw_from_nostra(ref self: TContractState, amount: u256);

    // --- Yield Operations ---
    fn harvest_all(ref self: TContractState) -> u256;
    fn harvest_vesu(ref self: TContractState) -> u256;
    fn harvest_ekubo(ref self: TContractState) -> u256;
    fn harvest_nostra(ref self: TContractState) -> u256;

    // --- Rebalancing ---
    fn set_target_allocations(
        ref self: TContractState,
        vesu_bps: u256,
        ekubo_bps: u256,
        nostra_bps: u256,
    );
    fn rebalance(ref self: TContractState);

    // --- Emergency ---
    fn emergency_withdraw_all(ref self: TContractState) -> u256;
    fn pause_strategy(ref self: TContractState, strategy_id: u32);
    fn unpause_strategy(ref self: TContractState, strategy_id: u32);

    // --- View Functions ---
    fn get_total_deployed(self: @TContractState) -> u256;
    fn get_total_pending_yield(self: @TContractState) -> u256;
    fn get_vesu_balance(self: @TContractState) -> u256;
    fn get_ekubo_balance(self: @TContractState) -> u256;
    fn get_nostra_balance(self: @TContractState) -> u256;
    fn get_vesu_pending_yield(self: @TContractState) -> u256;
    fn get_ekubo_pending_yield(self: @TContractState) -> u256;
    fn get_nostra_pending_yield(self: @TContractState) -> u256;
    fn get_target_allocation(self: @TContractState, strategy_id: u32) -> u256;
    fn get_adapter_address(self: @TContractState, strategy_id: u32) -> ContractAddress;
    fn is_strategy_paused(self: @TContractState, strategy_id: u32) -> bool;
}

#[starknet::contract]
mod StrategyManager {
    use core::traits::Into;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::info::get_block_timestamp;

    use reddio_cairo::interfaces::IERC20Dispatcher;
    use reddio_cairo::interfaces::IERC20DispatcherTrait;
    use reddio_cairo::interfaces::IStrategyAdapterDispatcher;
    use reddio_cairo::interfaces::IStrategyAdapterDispatcherTrait;

    // Strategy ID constants
    const VESU_ID: u32 = 0;
    const EKUBO_ID: u32 = 1;
    const NOSTRA_ID: u32 = 2;
    const STRATEGY_COUNT: u32 = 3;
    const BPS_DENOMINATOR: u256 = 10000;

    // ========================================================================
    // Storage
    // ========================================================================

    #[storage]
    struct Storage {
        // Core config
        initialized: bool,
        vault: ContractAddress,
        curator: ContractAddress,
        deposit_token: ContractAddress,

        // Adapter addresses
        vesu_adapter: ContractAddress,
        ekubo_adapter: ContractAddress,
        nostra_adapter: ContractAddress,

        // Target allocations in basis points (total must be <= 10000)
        target_vesu_bps: u256,
        target_ekubo_bps: u256,
        target_nostra_bps: u256,

        // Tracking
        total_deployed: u256,
        total_yield_harvested: u256,

        // Per-strategy pause state
        vesu_paused: bool,
        ekubo_paused: bool,
        nostra_paused: bool,

        // Last rebalance timestamp
        last_rebalance: u64,
    }

    // ========================================================================
    // Events
    // ========================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Initialized: Initialized,
        Deployed: Deployed,
        Withdrawn: Withdrawn,
        YieldHarvested: YieldHarvested,
        AllocationUpdated: AllocationUpdated,
        Rebalanced: Rebalanced,
        EmergencyWithdrawAll: EmergencyWithdrawAll,
        StrategyPaused: StrategyPaused,
        StrategyUnpaused: StrategyUnpaused,
    }

    #[derive(Drop, starknet::Event)]
    struct Initialized {
        vault: ContractAddress,
        curator: ContractAddress,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Deployed {
        #[key]
        strategy_id: u32,
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn {
        #[key]
        strategy_id: u32,
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct YieldHarvested {
        vesu_yield: u256,
        ekubo_yield: u256,
        nostra_yield: u256,
        total_yield: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct AllocationUpdated {
        vesu_bps: u256,
        ekubo_bps: u256,
        nostra_bps: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Rebalanced {
        total_deployed: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyWithdrawAll {
        total_recovered: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct StrategyPaused {
        strategy_id: u32,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct StrategyUnpaused {
        strategy_id: u32,
        timestamp: u64,
    }

    // ========================================================================
    // Implementation
    // ========================================================================

    #[abi(embed_v0)]
    impl StrategyManagerImpl of super::IStrategyManager<ContractState> {
        fn initialize(
            ref self: ContractState,
            vault: ContractAddress,
            curator: ContractAddress,
            deposit_token: ContractAddress,
            vesu_adapter: ContractAddress,
            ekubo_adapter: ContractAddress,
            nostra_adapter: ContractAddress,
        ) {
            assert(!self.initialized.read(), 'Already initialized');
            assert(vault != contract_address_const::<0>(), 'Invalid vault');
            assert(curator != contract_address_const::<0>(), 'Invalid curator');
            assert(deposit_token != contract_address_const::<0>(), 'Invalid token');
            assert(vesu_adapter != contract_address_const::<0>(), 'Invalid vesu adapter');
            assert(ekubo_adapter != contract_address_const::<0>(), 'Invalid ekubo adapter');
            assert(nostra_adapter != contract_address_const::<0>(), 'Invalid nostra adapter');

            self.initialized.write(true);
            self.vault.write(vault);
            self.curator.write(curator);
            self.deposit_token.write(deposit_token);
            self.vesu_adapter.write(vesu_adapter);
            self.ekubo_adapter.write(ekubo_adapter);
            self.nostra_adapter.write(nostra_adapter);

            // Default allocation: 40% Vesu, 30% Ekubo, 30% Nostra
            self.target_vesu_bps.write(4000);
            self.target_ekubo_bps.write(3000);
            self.target_nostra_bps.write(3000);

            self
                .emit(
                    Event::Initialized(
                        Initialized {
                            vault, curator, timestamp: get_block_timestamp(),
                        }
                    )
                );
        }

        // ================================================================
        // Capital Deployment
        // ================================================================

        fn deploy_to_vesu(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            assert(!self.vesu_paused.read(), 'Vesu strategy paused');
            self._deploy(VESU_ID, self.vesu_adapter.read(), amount);
        }

        fn deploy_to_ekubo(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            assert(!self.ekubo_paused.read(), 'Ekubo strategy paused');
            self._deploy(EKUBO_ID, self.ekubo_adapter.read(), amount);
        }

        fn deploy_to_nostra(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            assert(!self.nostra_paused.read(), 'Nostra strategy paused');
            self._deploy(NOSTRA_ID, self.nostra_adapter.read(), amount);
        }

        // ================================================================
        // Capital Withdrawal
        // ================================================================

        fn withdraw_from_vesu(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            self._withdraw(VESU_ID, self.vesu_adapter.read(), amount);
        }

        fn withdraw_from_ekubo(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            self._withdraw(EKUBO_ID, self.ekubo_adapter.read(), amount);
        }

        fn withdraw_from_nostra(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            self._withdraw(NOSTRA_ID, self.nostra_adapter.read(), amount);
        }

        // ================================================================
        // Yield Harvesting
        // ================================================================

        fn harvest_all(ref self: ContractState) -> u256 {
            self._only_vault_or_curator();

            let vesu_yield = self._harvest_adapter(self.vesu_adapter.read());
            let ekubo_yield = self._harvest_adapter(self.ekubo_adapter.read());
            let nostra_yield = self._harvest_adapter(self.nostra_adapter.read());

            let total = vesu_yield + ekubo_yield + nostra_yield;
            self.total_yield_harvested.write(self.total_yield_harvested.read() + total);

            self
                .emit(
                    Event::YieldHarvested(
                        YieldHarvested {
                            vesu_yield,
                            ekubo_yield,
                            nostra_yield,
                            total_yield: total,
                            timestamp: get_block_timestamp(),
                        }
                    )
                );

            total
        }

        fn harvest_vesu(ref self: ContractState) -> u256 {
            self._only_vault_or_curator();
            let y = self._harvest_adapter(self.vesu_adapter.read());
            self.total_yield_harvested.write(self.total_yield_harvested.read() + y);
            y
        }

        fn harvest_ekubo(ref self: ContractState) -> u256 {
            self._only_vault_or_curator();
            let y = self._harvest_adapter(self.ekubo_adapter.read());
            self.total_yield_harvested.write(self.total_yield_harvested.read() + y);
            y
        }

        fn harvest_nostra(ref self: ContractState) -> u256 {
            self._only_vault_or_curator();
            let y = self._harvest_adapter(self.nostra_adapter.read());
            self.total_yield_harvested.write(self.total_yield_harvested.read() + y);
            y
        }

        // ================================================================
        // Rebalancing
        // ================================================================

        fn set_target_allocations(
            ref self: ContractState,
            vesu_bps: u256,
            ekubo_bps: u256,
            nostra_bps: u256,
        ) {
            self._only_curator();
            assert(vesu_bps + ekubo_bps + nostra_bps <= BPS_DENOMINATOR, 'Total exceeds 100%');

            self.target_vesu_bps.write(vesu_bps);
            self.target_ekubo_bps.write(ekubo_bps);
            self.target_nostra_bps.write(nostra_bps);

            self
                .emit(
                    Event::AllocationUpdated(
                        AllocationUpdated {
                            vesu_bps,
                            ekubo_bps,
                            nostra_bps,
                            timestamp: get_block_timestamp(),
                        }
                    )
                );
        }

        fn rebalance(ref self: ContractState) {
            self._only_curator();

            // Get current balances from each adapter
            let vesu = IStrategyAdapterDispatcher {
                contract_address: self.vesu_adapter.read(),
            };
            let ekubo = IStrategyAdapterDispatcher {
                contract_address: self.ekubo_adapter.read(),
            };
            let nostra = IStrategyAdapterDispatcher {
                contract_address: self.nostra_adapter.read(),
            };

            let vesu_bal = vesu.get_total_balance();
            let ekubo_bal = ekubo.get_total_balance();
            let nostra_bal = nostra.get_total_balance();

            let total = vesu_bal + ekubo_bal + nostra_bal;

            // Calculate target amounts based on allocation percentages
            let target_vesu = (total * self.target_vesu_bps.read()) / BPS_DENOMINATOR;
            let target_ekubo = (total * self.target_ekubo_bps.read()) / BPS_DENOMINATOR;
            let target_nostra = (total * self.target_nostra_bps.read()) / BPS_DENOMINATOR;

            // Store target amounts for off-chain rebalancing execution
            // Actual fund movements are done via deploy/withdraw calls
            // to avoid complex multi-step atomic transactions
            self.total_deployed.write(total);
            self.last_rebalance.write(get_block_timestamp());

            // Emit target vs actual for monitoring
            // Off-chain keeper or curator uses these to execute rebalance steps:
            //   1. Withdraw excess from over-allocated strategies
            //   2. Deploy surplus to under-allocated strategies
            let _ = target_vesu;
            let _ = target_ekubo;
            let _ = target_nostra;

            self
                .emit(
                    Event::Rebalanced(
                        Rebalanced {
                            total_deployed: total, timestamp: get_block_timestamp(),
                        }
                    )
                );
        }

        // ================================================================
        // Emergency
        // ================================================================

        fn emergency_withdraw_all(ref self: ContractState) -> u256 {
            self._only_curator();

            let vesu = IStrategyAdapterDispatcher {
                contract_address: self.vesu_adapter.read(),
            };
            let ekubo = IStrategyAdapterDispatcher {
                contract_address: self.ekubo_adapter.read(),
            };
            let nostra = IStrategyAdapterDispatcher {
                contract_address: self.nostra_adapter.read(),
            };

            let r1 = vesu.emergency_withdraw();
            let r2 = ekubo.emergency_withdraw();
            let r3 = nostra.emergency_withdraw();

            let total = r1 + r2 + r3;
            self.total_deployed.write(0);

            self.vesu_paused.write(true);
            self.ekubo_paused.write(true);
            self.nostra_paused.write(true);

            self
                .emit(
                    Event::EmergencyWithdrawAll(
                        EmergencyWithdrawAll {
                            total_recovered: total, timestamp: get_block_timestamp(),
                        }
                    )
                );

            total
        }

        fn pause_strategy(ref self: ContractState, strategy_id: u32) {
            self._only_curator();
            if strategy_id == VESU_ID {
                self.vesu_paused.write(true);
            } else if strategy_id == EKUBO_ID {
                self.ekubo_paused.write(true);
            } else if strategy_id == NOSTRA_ID {
                self.nostra_paused.write(true);
            } else {
                assert(false, 'Invalid strategy ID');
            }

            self
                .emit(
                    Event::StrategyPaused(
                        StrategyPaused { strategy_id, timestamp: get_block_timestamp() }
                    )
                );
        }

        fn unpause_strategy(ref self: ContractState, strategy_id: u32) {
            self._only_curator();
            if strategy_id == VESU_ID {
                self.vesu_paused.write(false);
            } else if strategy_id == EKUBO_ID {
                self.ekubo_paused.write(false);
            } else if strategy_id == NOSTRA_ID {
                self.nostra_paused.write(false);
            } else {
                assert(false, 'Invalid strategy ID');
            }

            self
                .emit(
                    Event::StrategyUnpaused(
                        StrategyUnpaused { strategy_id, timestamp: get_block_timestamp() }
                    )
                );
        }

        // ================================================================
        // View Functions
        // ================================================================

        fn get_total_deployed(self: @ContractState) -> u256 {
            let vesu = IStrategyAdapterDispatcher {
                contract_address: self.vesu_adapter.read(),
            };
            let ekubo = IStrategyAdapterDispatcher {
                contract_address: self.ekubo_adapter.read(),
            };
            let nostra = IStrategyAdapterDispatcher {
                contract_address: self.nostra_adapter.read(),
            };

            vesu.get_total_balance() + ekubo.get_total_balance() + nostra.get_total_balance()
        }

        fn get_total_pending_yield(self: @ContractState) -> u256 {
            let vesu = IStrategyAdapterDispatcher {
                contract_address: self.vesu_adapter.read(),
            };
            let ekubo = IStrategyAdapterDispatcher {
                contract_address: self.ekubo_adapter.read(),
            };
            let nostra = IStrategyAdapterDispatcher {
                contract_address: self.nostra_adapter.read(),
            };

            vesu.get_pending_yield() + ekubo.get_pending_yield() + nostra.get_pending_yield()
        }

        fn get_vesu_balance(self: @ContractState) -> u256 {
            IStrategyAdapterDispatcher { contract_address: self.vesu_adapter.read() }
                .get_total_balance()
        }

        fn get_ekubo_balance(self: @ContractState) -> u256 {
            IStrategyAdapterDispatcher { contract_address: self.ekubo_adapter.read() }
                .get_total_balance()
        }

        fn get_nostra_balance(self: @ContractState) -> u256 {
            IStrategyAdapterDispatcher { contract_address: self.nostra_adapter.read() }
                .get_total_balance()
        }

        fn get_vesu_pending_yield(self: @ContractState) -> u256 {
            IStrategyAdapterDispatcher { contract_address: self.vesu_adapter.read() }
                .get_pending_yield()
        }

        fn get_ekubo_pending_yield(self: @ContractState) -> u256 {
            IStrategyAdapterDispatcher { contract_address: self.ekubo_adapter.read() }
                .get_pending_yield()
        }

        fn get_nostra_pending_yield(self: @ContractState) -> u256 {
            IStrategyAdapterDispatcher { contract_address: self.nostra_adapter.read() }
                .get_pending_yield()
        }

        fn get_target_allocation(self: @ContractState, strategy_id: u32) -> u256 {
            if strategy_id == VESU_ID {
                self.target_vesu_bps.read()
            } else if strategy_id == EKUBO_ID {
                self.target_ekubo_bps.read()
            } else if strategy_id == NOSTRA_ID {
                self.target_nostra_bps.read()
            } else {
                0
            }
        }

        fn get_adapter_address(self: @ContractState, strategy_id: u32) -> ContractAddress {
            if strategy_id == VESU_ID {
                self.vesu_adapter.read()
            } else if strategy_id == EKUBO_ID {
                self.ekubo_adapter.read()
            } else if strategy_id == NOSTRA_ID {
                self.nostra_adapter.read()
            } else {
                contract_address_const::<0>()
            }
        }

        fn is_strategy_paused(self: @ContractState, strategy_id: u32) -> bool {
            if strategy_id == VESU_ID {
                self.vesu_paused.read()
            } else if strategy_id == EKUBO_ID {
                self.ekubo_paused.read()
            } else if strategy_id == NOSTRA_ID {
                self.nostra_paused.read()
            } else {
                true
            }
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

        fn _deploy(
            ref self: ContractState,
            strategy_id: u32,
            adapter_addr: ContractAddress,
            amount: u256,
        ) {
            assert(amount > 0, 'Amount must be > 0');

            // Transfer tokens from this contract to the adapter
            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };
            token.transfer(adapter_addr, amount);

            // Tell the adapter to deposit into the protocol
            let adapter = IStrategyAdapterDispatcher { contract_address: adapter_addr };
            adapter.deposit(amount);

            self.total_deployed.write(self.total_deployed.read() + amount);

            self
                .emit(
                    Event::Deployed(
                        Deployed { strategy_id, amount, timestamp: get_block_timestamp() }
                    )
                );
        }

        fn _withdraw(
            ref self: ContractState,
            strategy_id: u32,
            adapter_addr: ContractAddress,
            amount: u256,
        ) {
            assert(amount > 0, 'Amount must be > 0');

            let adapter = IStrategyAdapterDispatcher { contract_address: adapter_addr };
            adapter.withdraw(amount);

            let current = self.total_deployed.read();
            if amount <= current {
                self.total_deployed.write(current - amount);
            } else {
                self.total_deployed.write(0);
            }

            self
                .emit(
                    Event::Withdrawn(
                        Withdrawn { strategy_id, amount, timestamp: get_block_timestamp() }
                    )
                );
        }

        fn _harvest_adapter(ref self: ContractState, adapter_addr: ContractAddress) -> u256 {
            let adapter = IStrategyAdapterDispatcher { contract_address: adapter_addr };
            adapter.harvest()
        }
    }
}
