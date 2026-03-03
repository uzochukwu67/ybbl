use starknet::ContractAddress;

// ============================================================================
// Nostra Money Market Strategy
// Deploys vault funds into Nostra lending/money market to earn supply APY.
// Similar to Vesu but targets Nostra's money market pools, providing
// diversification across lending protocols.
// ============================================================================

#[starknet::contract]
mod NostraStrategy {
    use core::traits::Into;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::info::get_block_timestamp;

    use reddio_cairo::interfaces::IERC20Dispatcher;
    use reddio_cairo::interfaces::IERC20DispatcherTrait;
    use reddio_cairo::interfaces::INostraMarketDispatcher;
    use reddio_cairo::interfaces::INostraMarketDispatcherTrait;

    // ========================================================================
    // Storage
    // ========================================================================

    #[storage]
    struct Storage {
        // The vault that owns this strategy
        vault: ContractAddress,
        // The curator who can manage the strategy
        curator: ContractAddress,
        // The Nostra money market contract
        nostra_market: ContractAddress,
        // The deposit token (e.g., WBTC, ETH, USDC)
        deposit_token: ContractAddress,
        // Amount of principal deposited
        principal_deposited: u256,
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
        Supplied: Supplied,
        Withdrawn: Withdrawn,
        YieldHarvested: YieldHarvested,
        EmergencyWithdrawn: EmergencyWithdrawn,
    }

    #[derive(Drop, starknet::Event)]
    struct Supplied {
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn {
        amount: u256,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct YieldHarvested {
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
    trait INostraStrategyInit<TContractState> {
        fn initialize(
            ref self: TContractState,
            vault: ContractAddress,
            curator: ContractAddress,
            nostra_market: ContractAddress,
            deposit_token: ContractAddress,
        );
    }

    #[abi(embed_v0)]
    impl NostraStrategyInitImpl of INostraStrategyInit<ContractState> {
        fn initialize(
            ref self: ContractState,
            vault: ContractAddress,
            curator: ContractAddress,
            nostra_market: ContractAddress,
            deposit_token: ContractAddress,
        ) {
            assert(!self.initialized.read(), 'Already initialized');
            assert(vault != contract_address_const::<0>(), 'Invalid vault');
            assert(curator != contract_address_const::<0>(), 'Invalid curator');
            assert(nostra_market != contract_address_const::<0>(), 'Invalid nostra market');
            assert(deposit_token != contract_address_const::<0>(), 'Invalid token');

            self.initialized.write(true);
            self.vault.write(vault);
            self.curator.write(curator);
            self.nostra_market.write(nostra_market);
            self.deposit_token.write(deposit_token);
            self.paused.write(false);
        }
    }

    // ========================================================================
    // Strategy Adapter Implementation
    // ========================================================================

    #[abi(embed_v0)]
    impl StrategyAdapterImpl of reddio_cairo::interfaces::IStrategyAdapter<ContractState> {
        // ----------------------------------------------------------------
        // Supply tokens to Nostra money market
        // ----------------------------------------------------------------
        fn deposit(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            self._assert_not_paused();
            assert(amount > 0, 'Amount must be > 0');

            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };
            let this = get_contract_address();

            // Ensure we received the tokens
            let balance = token.balance_of(this);
            assert(balance >= amount, 'Insufficient token balance');

            // Approve Nostra market to spend tokens
            let market_addr = self.nostra_market.read();
            token.approve(market_addr, amount);

            // Supply to Nostra
            let market = INostraMarketDispatcher { contract_address: market_addr };
            market.supply(self.deposit_token.read(), amount);

            // Update accounting
            self.principal_deposited.write(self.principal_deposited.read() + amount);

            self.emit(Event::Supplied(Supplied { amount, timestamp: get_block_timestamp() }));
        }

        // ----------------------------------------------------------------
        // Withdraw tokens from Nostra money market back to vault
        // ----------------------------------------------------------------
        fn withdraw(ref self: ContractState, amount: u256) {
            self._only_vault_or_curator();
            assert(amount > 0, 'Amount must be > 0');

            let market = INostraMarketDispatcher { contract_address: self.nostra_market.read() };
            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };
            let this = get_contract_address();

            let balance_before = token.balance_of(this);

            // Withdraw from Nostra
            market.withdraw(self.deposit_token.read(), amount);

            let balance_after = token.balance_of(this);
            let actual_withdrawn = balance_after - balance_before;

            // Transfer to vault
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
        // Harvest: collect accrued lending yield
        // ----------------------------------------------------------------
        fn harvest(ref self: ContractState) -> u256 {
            self._only_vault_or_curator();
            self._assert_not_paused();

            let total_balance = self._get_supply_balance();
            let principal = self.principal_deposited.read();

            if total_balance <= principal {
                return 0;
            }

            let yield_amount = total_balance - principal;

            // Withdraw only the yield
            let market = INostraMarketDispatcher { contract_address: self.nostra_market.read() };
            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };

            market.withdraw(self.deposit_token.read(), yield_amount);

            // Send to vault
            token.transfer(self.vault.read(), yield_amount);

            // Update tracking
            self
                .total_yield_harvested
                .write(self.total_yield_harvested.read() + yield_amount);

            self
                .emit(
                    Event::YieldHarvested(
                        YieldHarvested { yield_amount, timestamp: get_block_timestamp() }
                    )
                );

            yield_amount
        }

        fn get_total_balance(self: @ContractState) -> u256 {
            self._get_supply_balance()
        }

        fn get_pending_yield(self: @ContractState) -> u256 {
            let total = self._get_supply_balance();
            let principal = self.principal_deposited.read();
            if total > principal {
                total - principal
            } else {
                0
            }
        }

        fn get_protocol(self: @ContractState) -> ContractAddress {
            self.nostra_market.read()
        }

        fn get_vault(self: @ContractState) -> ContractAddress {
            self.vault.read()
        }

        // ----------------------------------------------------------------
        // Emergency: withdraw everything and return to vault
        // ----------------------------------------------------------------
        fn emergency_withdraw(ref self: ContractState) -> u256 {
            self._only_curator();

            let total = self._get_supply_balance();
            if total == 0 {
                return 0;
            }

            let market = INostraMarketDispatcher { contract_address: self.nostra_market.read() };
            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };
            let this = get_contract_address();

            let balance_before = token.balance_of(this);
            market.withdraw(self.deposit_token.read(), total);
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

        fn _get_supply_balance(self: @ContractState) -> u256 {
            let market = INostraMarketDispatcher { contract_address: self.nostra_market.read() };
            market.get_supply_balance(self.deposit_token.read(), get_contract_address())
        }
    }
}
