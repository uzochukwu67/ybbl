/// Vesu Lending Strategy — lending pool management
/// Core Domain: supply/withdraw collateral via Vesu V2 modify_position
///
/// Implements IStrategy (common vault interface) + IVesuLendingStrategyExt.
/// Uses vendored Vesu interfaces from src/interfaces/vesu.cairo.

#[starknet::contract]
pub mod VesuLendingStrategy {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use alexandria_math::i257::I257Impl;

    // Vesu vendored types
    use super::super::super::interfaces::vesu::{
        IVesuPoolDispatcher, IVesuPoolDispatcherTrait,
        ModifyPositionParams, Amount, AmountDenomination,
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
        Supplied: Supplied,
        Withdrawn: Withdrawn,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Supplied {
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Withdrawn {
        pub amount: u256,
    }

    // ── Constants ──
    /// Zero address used as debt_asset (collateral-only, no borrowing)
    fn zero_address() -> ContractAddress {
        0.try_into().unwrap()
    }

    // ── Storage ──
    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        vault_addr: ContractAddress,
        manager_addr: ContractAddress,
        vesu_pool: ContractAddress,
        pool_id: felt252,
        asset: ContractAddress,    // wBTC — collateral asset
    }

    // ── Constructor ──
    #[constructor]
    fn constructor(
        ref self: ContractState,
        vault: ContractAddress,
        manager: ContractAddress,
        owner: ContractAddress,
        vesu_pool: ContractAddress,
        pool_id: felt252,
        asset: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.vault_addr.write(vault);
        self.manager_addr.write(manager);
        self.vesu_pool.write(vesu_pool);
        self.pool_id.write(pool_id);
        self.asset.write(asset);
    }

    // ── IStrategy Implementation ──
    #[abi(embed_v0)]
    impl StrategyImpl of super::super::traits::IStrategy<ContractState> {
        /// Deploy assets (wBTC) into Vesu lending pool as collateral.
        fn deposit(ref self: ContractState, amount: u256) {
            self._assert_vault_or_manager();
            assert(amount > 0, 'ZERO_AMOUNT');

            let asset_addr = self.asset.read();
            let pool_addr = self.vesu_pool.read();
            let asset_disp = IERC20Dispatcher { contract_address: asset_addr };

            // Strategy must already hold the funds (caller transfers before calling deposit)
            let bal = asset_disp.balance_of(get_contract_address());
            assert(bal >= amount, 'INSUFFICIENT_STRATEGY_BALANCE');

            // Approve pool to spend asset
            asset_disp.approve(pool_addr, amount);

            // Supply collateral via modify_position (positive collateral, zero debt)
            let pool_disp = IVesuPoolDispatcher { contract_address: pool_addr };
            let collateral_amount = Amount {
                denomination: AmountDenomination::Assets,
                value: I257Impl::new(amount, false),
            };
            let zero_debt = Amount {
                denomination: AmountDenomination::Assets,
                value: I257Impl::new(0, false),
            };

            pool_disp
                .modify_position(
                    ModifyPositionParams {
                        collateral_asset: asset_addr,
                        debt_asset: zero_address(),
                        user: get_contract_address(),
                        collateral: collateral_amount,
                        debt: zero_debt,
                    },
                );

            self.emit(Supplied { amount });
        }

        /// Withdraw assets (wBTC) from Vesu lending pool.
        ///
        /// `amount` may include idle wBTC sitting on this contract (from rounding
        /// dust or direct transfers).  We only ask the Vesu pool to withdraw up to
        /// the on-pool collateral so we never request more than is deposited.
        /// Any idle balance is automatically included in the final vault transfer.
        fn withdraw(ref self: ContractState, amount: u256) {
            self._assert_vault_or_manager();
            assert(amount > 0, 'ZERO_AMOUNT');

            let asset_addr = self.asset.read();
            let pool_addr = self.vesu_pool.read();
            let pool_disp = IVesuPoolDispatcher { contract_address: pool_addr };

            // Query on-pool collateral to cap the withdrawal amount
            let (position, _cv, _dv) = pool_disp
                .position(asset_addr, zero_address(), get_contract_address());
            let collateral_shares_i257 = I257Impl::new(
                position.collateral_shares, false,
            );
            let on_pool_collateral = pool_disp
                .calculate_collateral(asset_addr, collateral_shares_i257);

            // Only withdraw from pool if there is collateral to withdraw
            let pool_withdraw = if amount <= on_pool_collateral {
                amount
            } else {
                on_pool_collateral
            };

            if pool_withdraw > 0 {
                let collateral_amount = Amount {
                    denomination: AmountDenomination::Assets,
                    value: I257Impl::new(pool_withdraw, true),
                };
                let zero_debt = Amount {
                    denomination: AmountDenomination::Assets,
                    value: I257Impl::new(0, false),
                };

                pool_disp
                    .modify_position(
                        ModifyPositionParams {
                            collateral_asset: asset_addr,
                            debt_asset: zero_address(),
                            user: get_contract_address(),
                            collateral: collateral_amount,
                            debt: zero_debt,
                        },
                    );
            }

            // Transfer all available wBTC (pool-withdrawn + idle) to vault
            let vault = self.vault_addr.read();
            let asset_disp = IERC20Dispatcher { contract_address: asset_addr };
            let bal = asset_disp.balance_of(get_contract_address());
            if bal > 0 {
                let success = asset_disp.transfer(vault, bal);
                assert(success, 'WITHDRAW_TRANSFER_FAILED');
            }

            self.emit(Withdrawn { amount });
        }

        /// Total assets: collateral in Vesu pool + any idle wBTC on this contract.
        /// Idle balance can exist from rounding dust or direct transfers.
        fn total_assets(self: @ContractState) -> u256 {
            let pool_addr = self.vesu_pool.read();
            let asset_addr = self.asset.read();
            let pool_disp = IVesuPoolDispatcher { contract_address: pool_addr };

            // Query position state
            let (position, _collateral_value, _debt_value) = pool_disp
                .position(asset_addr, zero_address(), get_contract_address());

            // Convert collateral shares to actual asset amount
            let collateral_shares_i257 = I257Impl::new(
                position.collateral_shares, false,
            );
            let collateral = pool_disp.calculate_collateral(asset_addr, collateral_shares_i257);

            // Include any idle wBTC sitting on the strategy contract
            let asset_disp = IERC20Dispatcher { contract_address: asset_addr };
            let idle_balance = asset_disp.balance_of(get_contract_address());

            collateral + idle_balance
        }

        fn vault(self: @ContractState) -> ContractAddress {
            self.vault_addr.read()
        }
    }

    // ── IVesuLendingStrategyExt Implementation ──
    #[abi(embed_v0)]
    impl VesuLendingStrategyExtImpl of super::super::traits::IVesuLendingStrategyExt<
        ContractState,
    > {
        fn supply(ref self: ContractState, amount: u256) {
            self._assert_vault_or_manager();
            // Delegate to IStrategy::deposit
            StrategyImpl::deposit(ref self, amount);
        }

        fn withdraw_collateral(ref self: ContractState, amount: u256) {
            self._assert_vault_or_manager();
            // Delegate to IStrategy::withdraw
            StrategyImpl::withdraw(ref self, amount);
        }

        fn set_manager(ref self: ContractState, new_manager: ContractAddress) {
            self.ownable.assert_only_owner();
            self.manager_addr.write(new_manager);
        }

        fn current_apy(self: @ContractState) -> u256 {
            let pool_addr = self.vesu_pool.read();
            let asset_addr = self.asset.read();
            let pool_disp = IVesuPoolDispatcher { contract_address: pool_addr };

            // Get utilization rate as a proxy for APY
            // actual APY = f(utilization, rate model) — simplified here
            let utilization = pool_disp.utilization(asset_addr);

            // Rough estimate: APY_bps = utilization * base_rate / SCALE
            // For MVP, return raw utilization (0-1e18) as u256
            // Frontend converts to human-readable APY
            utilization
        }
    }

    // ── Internal Helpers ──
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _assert_vault_or_manager(self: @ContractState) {
            let caller = get_caller_address();
            let vault = self.vault_addr.read();
            let manager = self.manager_addr.read();
            assert(caller == vault || caller == manager, 'ONLY_VAULT_OR_MANAGER');
        }
    }
}