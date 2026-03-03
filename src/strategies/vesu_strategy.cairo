use starknet::ContractAddress;

// ============================================================================
// Vesu Lending Strategy
// Deploys vault funds into Vesu lending pools to earn supply interest.
// The curator configures the target pool, and the adapter handles
// deposit/withdraw/harvest operations against the Vesu protocol.
// ============================================================================

#[starknet::contract]
mod VesuStrategy {
    use core::traits::Into;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::info::get_block_timestamp;

    use reddio_cairo::interfaces::IERC20Dispatcher;
    use reddio_cairo::interfaces::IERC20DispatcherTrait;
    use reddio_cairo::interfaces::IVesuPoolDispatcher;
    use reddio_cairo::interfaces::IVesuPoolDispatcherTrait;

    // ========================================================================
    // Storage
    // ========================================================================

    #[storage]
    struct Storage {
        // The vault that owns this strategy
        vault: ContractAddress,
        // The curator who can manage the strategy
        curator: ContractAddress,
        // The Vesu lending pool contract
        vesu_pool: ContractAddress,
        // The deposit token (e.g., WBTC, ETH, USDC)
        deposit_token: ContractAddress,
        // Amount of principal deposited via this strategy
        principal_deposited: u256,
        // Total yield harvested historically
        total_yield_harvested: u256,
        // Whether the strategy is initialized
        initialized: bool,
        // Whether the strategy is paused (emergency)
        paused: bool,
    }

    // ========================================================================
    // Events
    // ========================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposited: Deposited,
        Withdrawn: Withdrawn,
        Harvested: Harvested,
        EmergencyWithdrawn: EmergencyWithdrawn,
        Paused: Paused,
        Unpaused: Unpaused,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposited {
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn {
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Harvested {
        yield_amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct EmergencyWithdrawn {
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Paused {
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Unpaused {
        timestamp: u64,
    }

    // ========================================================================
    // Constructor-like Initialization
    // ========================================================================

    #[starknet::interface]
    trait IVesuStrategyInit<TContractState> {
        fn initialize(
            ref self: TContractState,
            vault: ContractAddress,
            curator: ContractAddress,
            vesu_pool: ContractAddress,
            deposit_token: ContractAddress,
        );
    }

    // ========================================================================
    // Implementation
    // ========================================================================

    #[abi(embed_v0)]
    impl VesuStrategyInitImpl of IVesuStrategyInit<ContractState> {
        fn initialize(
            ref self: ContractState,
            vault: ContractAddress,
            curator: ContractAddress,
            vesu_pool: ContractAddress,
            deposit_token: ContractAddress,
        ) {
            assert(!self.initialized.read(), 'Already initialized');
            assert(vault != contract_address_const::<0>(), 'Invalid vault');
            assert(curator != contract_address_const::<0>(), 'Invalid curator');
            assert(vesu_pool != contract_address_const::<0>(), 'Invalid vesu pool');
            assert(deposit_token != contract_address_const::<0>(), 'Invalid token');

            self.initialized.write(true);
            self.vault.write(vault);
            self.curator.write(curator);
            self.vesu_pool.write(vesu_pool);
            self.deposit_token.write(deposit_token);
            self.paused.write(false);
        }
    }

    #[abi(embed_v0)]
    impl StrategyAdapterImpl of reddio_cairo::interfaces::IStrategyAdapter<ContractState> {
        // ----------------------------------------------------------------
        // Deposit tokens into Vesu lending pool
        // Called by the vault when deploying funds to this strategy
        // ----------------------------------------------------------------
        fn deposit(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            self._assert_not_paused();
            assert(amount > 0, 'Amount must be > 0');

            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };
            let this = get_contract_address();

            // Ensure we have the tokens (transferred from vault)
            let balance = token.balance_of(this);
            assert(balance >= amount, 'Insufficient token balance');

            // Approve Vesu pool to spend tokens
            let pool_addr = self.vesu_pool.read();
            token.approve(pool_addr, amount);

            // Deposit into Vesu lending pool
            let pool = IVesuPoolDispatcher { contract_address: pool_addr };
            pool.deposit(self.deposit_token.read(), amount);

            // Update accounting
            self.principal_deposited.write(self.principal_deposited.read() + amount);

            self.emit(Event::Deposited(Deposited { amount, timestamp: get_block_timestamp() }));
        }

        // ----------------------------------------------------------------
        // Withdraw tokens from Vesu lending pool back to vault
        // ----------------------------------------------------------------
        fn withdraw(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            assert(amount > 0, 'Amount must be > 0');

            let pool = IVesuPoolDispatcher { contract_address: self.vesu_pool.read() };
            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };
            let this = get_contract_address();

            let balance_before = token.balance_of(this);

            // Withdraw from Vesu pool
            pool.withdraw(self.deposit_token.read(), amount);

            let balance_after = token.balance_of(this);
            let actual_withdrawn = balance_after - balance_before;

            // Transfer withdrawn funds back to vault
            token.transfer(self.vault.read(), actual_withdrawn);

            // Update accounting
            let principal = self.principal_deposited.read();
            if actual_withdrawn <= principal {
                self.principal_deposited.write(principal - actual_withdrawn);
            } else {
                self.principal_deposited.write(0);
            }

            self
                .emit(
                    Event::Withdrawn(
                        Withdrawn { amount: actual_withdrawn, timestamp: get_block_timestamp() }
                    )
                );
        }

        // ----------------------------------------------------------------
        // Harvest yield: claim accrued interest and send to vault
        // ----------------------------------------------------------------
        fn harvest(ref self: ContractState) -> u256 {
            self._only_vault_or_curator();
            self._assert_not_paused();

            let total_balance = self._get_pool_balance();
            let principal = self.principal_deposited.read();

            if total_balance <= principal {
                return 0;
            }

            let yield_amount = total_balance - principal;

            // Withdraw only the yield portion
            let pool = IVesuPoolDispatcher { contract_address: self.vesu_pool.read() };
            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };

            pool.withdraw(self.deposit_token.read(), yield_amount);

            // Transfer yield to vault
            token.transfer(self.vault.read(), yield_amount);

            // Update yield tracking
            self
                .total_yield_harvested
                .write(self.total_yield_harvested.read() + yield_amount);

            self
                .emit(
                    Event::Harvested(
                        Harvested { yield_amount, timestamp: get_block_timestamp() }
                    )
                );

            yield_amount
        }

        // ----------------------------------------------------------------
        // View: total balance in the Vesu pool (principal + accrued yield)
        // ----------------------------------------------------------------
        fn get_total_balance(self: @ContractState) -> u256 {
            self._get_pool_balance()
        }

        // ----------------------------------------------------------------
        // View: pending unharvested yield
        // ----------------------------------------------------------------
        fn get_pending_yield(self: @ContractState) -> u256 {
            let total = self._get_pool_balance();
            let principal = self.principal_deposited.read();
            if total > principal {
                total - principal
            } else {
                0
            }
        }

        fn get_protocol(self: @ContractState) -> ContractAddress {
            self.vesu_pool.read()
        }

        fn get_vault(self: @ContractState) -> ContractAddress {
            self.vault.read()
        }

        // ----------------------------------------------------------------
        // Emergency: withdraw everything and send back to vault
        // ----------------------------------------------------------------
        fn emergency_withdraw(ref self: ContractState) -> u256 {
            self._only_curator();

            let total = self._get_pool_balance();
            if total == 0 {
                return 0;
            }

            let pool = IVesuPoolDispatcher { contract_address: self.vesu_pool.read() };
            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };
            let this = get_contract_address();

            let balance_before = token.balance_of(this);
            pool.withdraw(self.deposit_token.read(), total);
            let balance_after = token.balance_of(this);
            let recovered = balance_after - balance_before;

            // Send everything to vault
            token.transfer(self.vault.read(), recovered);

            // Reset accounting
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

        fn _get_pool_balance(self: @ContractState) -> u256 {
            let pool = IVesuPoolDispatcher { contract_address: self.vesu_pool.read() };
            pool.get_deposit_balance(self.deposit_token.read(), get_contract_address())
        }
    }
}
