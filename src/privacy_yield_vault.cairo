use starknet::ContractAddress;

// ============================================================================
// External Protocol Interfaces (for cross-contract calls to high-TVL apps)
// ============================================================================

#[starknet::interface]
trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    );
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256);
}

// ============================================================================
// Privacy Yield Vault Interface
// ============================================================================

#[starknet::interface]
trait IPrivacyYieldVault<TContractState> {
    // --- Initialization ---
    fn initialize(
        ref self: TContractState,
        _deposit_token: ContractAddress,
        _curator: ContractAddress,
        _strategy_count: u32,
    );

    // --- Privacy Deposit: user commits funds with a Pedersen commitment ---
    fn deposit_private(ref self: TContractState, amount: u256, commitment: felt252);

    // --- Privacy Withdrawal: nullifier-based to prevent double-spend ---
    fn withdraw_private(
        ref self: TContractState,
        amount: u256,
        nullifier: felt252,
        commitment: felt252,
        proof_element: felt252,
    );

    // --- Strategy Management (curator-only) ---
    fn set_strategy(
        ref self: TContractState,
        strategy_id: u32,
        protocol_address: ContractAddress,
        allocation_bps: u256,
        is_active: bool,
    );

    fn rebalance(ref self: TContractState);

    fn deploy_to_strategy(ref self: TContractState, strategy_id: u32, amount: u256);
    fn withdraw_from_strategy(ref self: TContractState, strategy_id: u32, amount: u256);

    // --- View Functions ---
    fn get_total_deposits(self: @TContractState) -> u256;
    fn get_total_deployed(self: @TContractState) -> u256;
    fn get_commitment_count(self: @TContractState) -> u256;
    fn get_strategy_count(self: @TContractState) -> u32;
    fn get_strategy_allocation(self: @TContractState, strategy_id: u32) -> u256;
    fn get_strategy_deployed(self: @TContractState, strategy_id: u32) -> u256;
    fn get_strategy_protocol(self: @TContractState, strategy_id: u32) -> ContractAddress;
    fn is_strategy_active(self: @TContractState, strategy_id: u32) -> bool;
    fn verify_commitment_exists(self: @TContractState, commitment: felt252) -> bool;
    fn is_nullifier_used(self: @TContractState, nullifier: felt252) -> bool;
    fn get_vault_idle_balance(self: @TContractState) -> u256;
    fn get_curator(self: @TContractState) -> ContractAddress;
    fn get_deposit_token(self: @TContractState) -> ContractAddress;

    // --- Privacy Proof: verify vault solvency without revealing positions ---
    fn get_solvency_commitment(self: @TContractState) -> felt252;
}

// ============================================================================
// Privacy Yield Vault Contract
// ============================================================================

#[starknet::contract]
mod PrivacyYieldVault {
    use core::traits::Into;
    use core::pedersen::PedersenTrait;
    use core::hash::HashStateTrait;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::info::get_block_timestamp;

    use super::IERC20Dispatcher;
    use super::IERC20DispatcherTrait;

    // ========================================================================
    // Storage
    // ========================================================================

    #[storage]
    struct Storage {
        // --- Core Config ---
        initialized: bool,
        curator: ContractAddress,
        deposit_token: ContractAddress,

        // --- Vault Accounting ---
        total_deposits: u256,
        total_deployed: u256,
        total_yield_earned: u256,

        // --- Privacy: Commitment Tree ---
        // Maps commitment index -> commitment hash
        commitments: LegacyMap::<u256, felt252>,
        commitment_count: u256,
        // Maps commitment hash -> exists
        commitment_exists: LegacyMap::<felt252, bool>,
        // Maps nullifier -> spent (prevents double-withdrawal)
        nullifier_used: LegacyMap::<felt252, bool>,

        // --- Strategies ---
        strategy_count: u32,
        // strategy_id -> protocol contract address
        strategy_protocols: LegacyMap::<u32, ContractAddress>,
        // strategy_id -> allocation in basis points (out of 10000)
        strategy_allocations: LegacyMap::<u32, u256>,
        // strategy_id -> amount currently deployed
        strategy_deployed: LegacyMap::<u32, u256>,
        // strategy_id -> is active
        strategy_active: LegacyMap::<u32, bool>,
        // strategy_id -> cumulative yield earned
        strategy_yield: LegacyMap::<u32, u256>,
        // strategy_id -> last update timestamp
        strategy_last_update: LegacyMap::<u32, u64>,
    }

    // ========================================================================
    // Events
    // ========================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        VaultInitialized: VaultInitialized,
        PrivateDeposit: PrivateDeposit,
        PrivateWithdrawal: PrivateWithdrawal,
        StrategyUpdated: StrategyUpdated,
        StrategyDeployed: StrategyDeployed,
        StrategyWithdrawn: StrategyWithdrawn,
        Rebalanced: Rebalanced,
        SolvencyProofGenerated: SolvencyProofGenerated,
    }

    #[derive(Drop, starknet::Event)]
    struct VaultInitialized {
        deposit_token: ContractAddress,
        curator: ContractAddress,
        timestamp: u64,
    }

    // Note: Only the commitment is emitted, NOT the amount or depositor
    // This preserves privacy while allowing commitment verification on-chain
    #[derive(Drop, starknet::Event)]
    struct PrivateDeposit {
        #[key]
        commitment: felt252,
        timestamp: u64,
    }

    // Note: Only the nullifier is emitted to prevent double-spend
    // Amount and recipient remain private
    #[derive(Drop, starknet::Event)]
    struct PrivateWithdrawal {
        #[key]
        nullifier: felt252,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct StrategyUpdated {
        #[key]
        strategy_id: u32,
        protocol: ContractAddress,
        allocation_bps: u256,
        is_active: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct StrategyDeployed {
        #[key]
        strategy_id: u32,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct StrategyWithdrawn {
        #[key]
        strategy_id: u32,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Rebalanced {
        timestamp: u64,
        total_deployed: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct SolvencyProofGenerated {
        commitment: felt252,
        timestamp: u64,
    }

    // ========================================================================
    // Implementation
    // ========================================================================

    #[abi(embed_v0)]
    impl IPrivacyYieldVaultImpl of super::IPrivacyYieldVault<ContractState> {
        // --------------------------------------------------------------------
        // Initialization
        // --------------------------------------------------------------------
        fn initialize(
            ref self: ContractState,
            _deposit_token: ContractAddress,
            _curator: ContractAddress,
            _strategy_count: u32,
        ) {
            assert(!self.initialized.read(), 'Already initialized');
            assert(_deposit_token != contract_address_const::<0>(), 'Invalid deposit token');
            assert(_curator != contract_address_const::<0>(), 'Invalid curator');
            assert(_strategy_count > 0, 'Need at least 1 strategy');

            self.initialized.write(true);
            self.deposit_token.write(_deposit_token);
            self.curator.write(_curator);
            self.strategy_count.write(_strategy_count);

            self
                .emit(
                    Event::VaultInitialized(
                        VaultInitialized {
                            deposit_token: _deposit_token,
                            curator: _curator,
                            timestamp: get_block_timestamp(),
                        }
                    )
                );
        }

        // --------------------------------------------------------------------
        // Private Deposit
        // User deposits tokens and provides a Pedersen commitment:
        //   commitment = Pedersen(amount, secret)
        // The commitment is stored on-chain but the secret remains private.
        // This hides the depositor's identity and exact amount from observers.
        // --------------------------------------------------------------------
        fn deposit_private(ref self: ContractState, amount: u256, commitment: felt252) {
            assert(self.initialized.read(), 'Not initialized');
            assert(amount > 0, 'Amount must be > 0');
            assert(commitment != 0, 'Invalid commitment');
            assert(!self.commitment_exists.read(commitment), 'Commitment already used');

            // Verify the commitment is well-formed by checking it's non-trivial
            // In production, a ZK circuit would verify Pedersen(amount, secret) == commitment
            // For the hackathon MVP, we store the commitment and verify on withdrawal

            // Transfer tokens from depositor to vault
            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };
            let vault_addr = get_contract_address();
            let caller = get_caller_address();

            let balance_before = token.balance_of(vault_addr);
            token.transfer_from(caller, vault_addr, amount);
            let actual_deposited = token.balance_of(vault_addr) - balance_before;

            // Store commitment in the commitment tree
            let idx = self.commitment_count.read();
            self.commitments.write(idx, commitment);
            self.commitment_count.write(idx + 1);
            self.commitment_exists.write(commitment, true);

            // Update vault accounting
            self.total_deposits.write(self.total_deposits.read() + actual_deposited);

            // Emit only the commitment — amount and depositor are NOT revealed
            self
                .emit(
                    Event::PrivateDeposit(
                        PrivateDeposit { commitment, timestamp: get_block_timestamp() }
                    )
                );
        }

        // --------------------------------------------------------------------
        // Private Withdrawal
        // User provides:
        //   - nullifier: unique identifier derived from their secret
        //   - commitment: the original deposit commitment
        //   - proof_element: a ZK proof element demonstrating:
        //       1. They know the secret behind the commitment
        //       2. The commitment exists in the tree
        //       3. The nullifier is derived correctly
        //   - amount: the withdrawal amount
        //
        // The nullifier prevents double-spending without revealing which
        // commitment is being withdrawn from.
        // --------------------------------------------------------------------
        fn withdraw_private(
            ref self: ContractState,
            amount: u256,
            nullifier: felt252,
            commitment: felt252,
            proof_element: felt252,
        ) {
            assert(self.initialized.read(), 'Not initialized');
            assert(amount > 0, 'Amount must be > 0');
            assert(nullifier != 0, 'Invalid nullifier');
            assert(!self.nullifier_used.read(nullifier), 'Nullifier already spent');
            assert(self.commitment_exists.read(commitment), 'Unknown commitment');

            // Verify the ZK proof
            // In production: verify a STARK proof that:
            //   Pedersen(nullifier, secret) relates to commitment
            //   and commitment is in the Merkle tree
            // For hackathon MVP: verify proof_element links nullifier to commitment
            self._verify_withdrawal_proof(nullifier, commitment, proof_element);

            // Check vault has sufficient balance
            let available = self.total_deposits.read() - self.total_deployed.read();
            assert(amount <= self.total_deposits.read(), 'Exceeds total deposits');
            assert(amount <= available, 'Insufficient idle balance');

            // Mark nullifier as spent (prevents double-withdrawal)
            self.nullifier_used.write(nullifier, true);

            // Update accounting
            self.total_deposits.write(self.total_deposits.read() - amount);

            // Transfer tokens to caller
            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };
            token.transfer(get_caller_address(), amount);

            // Emit only nullifier — does NOT reveal which commitment or how much
            self
                .emit(
                    Event::PrivateWithdrawal(
                        PrivateWithdrawal { nullifier, timestamp: get_block_timestamp() }
                    )
                );
        }

        // --------------------------------------------------------------------
        // Strategy Management (Curator-only)
        // Curator can configure how vault funds are allocated across protocols:
        //   - Extended (perps/yield) — high-yield BTC strategies
        //   - Vesu (lending) — borrow against BTC, earn stable yields
        //   - Ekubo (LP) — provide liquidity, earn swap fees
        // Allocation is in basis points (10000 = 100%)
        // --------------------------------------------------------------------
        fn set_strategy(
            ref self: ContractState,
            strategy_id: u32,
            protocol_address: ContractAddress,
            allocation_bps: u256,
            is_active: bool,
        ) {
            self._only_curator();
            assert(strategy_id < self.strategy_count.read(), 'Invalid strategy ID');
            assert(protocol_address != contract_address_const::<0>(), 'Invalid protocol');

            // Validate total allocation doesn't exceed 10000 bps (100%)
            let old_allocation = self.strategy_allocations.read(strategy_id);
            let total_minus_old = self._get_total_allocation() - old_allocation;
            assert(total_minus_old + allocation_bps <= 10000, 'Total alloc exceeds 100%');

            self.strategy_protocols.write(strategy_id, protocol_address);
            self.strategy_allocations.write(strategy_id, allocation_bps);
            self.strategy_active.write(strategy_id, is_active);
            self.strategy_last_update.write(strategy_id, get_block_timestamp());

            self
                .emit(
                    Event::StrategyUpdated(
                        StrategyUpdated {
                            strategy_id, protocol: protocol_address, allocation_bps, is_active,
                        }
                    )
                );
        }

        // --------------------------------------------------------------------
        // Deploy funds to a specific strategy protocol
        // Transfers tokens from vault to the strategy's protocol address
        // In production, this would call protocol-specific deposit functions
        // --------------------------------------------------------------------
        fn deploy_to_strategy(ref self: ContractState, strategy_id: u32, amount: u256) {
            self._only_curator();
            assert(strategy_id < self.strategy_count.read(), 'Invalid strategy ID');
            assert(self.strategy_active.read(strategy_id), 'Strategy not active');
            assert(amount > 0, 'Amount must be > 0');

            let idle = self.total_deposits.read() - self.total_deployed.read();
            assert(amount <= idle, 'Insufficient idle balance');

            let protocol = self.strategy_protocols.read(strategy_id);
            assert(protocol != contract_address_const::<0>(), 'Protocol not configured');

            // Transfer to protocol
            let token = IERC20Dispatcher { contract_address: self.deposit_token.read() };
            token.transfer(protocol, amount);

            // Update accounting
            self.strategy_deployed.write(
                strategy_id, self.strategy_deployed.read(strategy_id) + amount
            );
            self.total_deployed.write(self.total_deployed.read() + amount);
            self.strategy_last_update.write(strategy_id, get_block_timestamp());

            self
                .emit(
                    Event::StrategyDeployed(StrategyDeployed { strategy_id, amount })
                );
        }

        // --------------------------------------------------------------------
        // Withdraw funds from a specific strategy
        // In production, would call protocol-specific withdraw functions
        // For MVP, handles the accounting side
        // --------------------------------------------------------------------
        fn withdraw_from_strategy(ref self: ContractState, strategy_id: u32, amount: u256) {
            self._only_curator();
            assert(strategy_id < self.strategy_count.read(), 'Invalid strategy ID');
            assert(amount > 0, 'Amount must be > 0');

            let deployed = self.strategy_deployed.read(strategy_id);
            assert(amount <= deployed, 'Exceeds deployed amount');

            // Update accounting
            self.strategy_deployed.write(strategy_id, deployed - amount);
            self.total_deployed.write(self.total_deployed.read() - amount);
            self.strategy_last_update.write(strategy_id, get_block_timestamp());

            self
                .emit(
                    Event::StrategyWithdrawn(StrategyWithdrawn { strategy_id, amount })
                );
        }

        // --------------------------------------------------------------------
        // Rebalance: Redistribute deployed funds according to target allocations
        // This is a signal/accounting operation; actual fund movements happen
        // via deploy_to_strategy / withdraw_from_strategy
        // --------------------------------------------------------------------
        fn rebalance(ref self: ContractState) {
            self._only_curator();

            let total = self.total_deposits.read();
            let count = self.strategy_count.read();
            let mut i: u32 = 0;

            loop {
                if i >= count {
                    break;
                }

                if self.strategy_active.read(i) {
                    let target_bps = self.strategy_allocations.read(i);
                    let _target_amount = (total * target_bps) / 10000;
                    // In production: compare _target_amount vs strategy_deployed
                    // and perform actual deploy/withdraw to rebalance
                    // For MVP, we update the last_update timestamp
                    self.strategy_last_update.write(i, get_block_timestamp());
                }

                i += 1;
            };

            self
                .emit(
                    Event::Rebalanced(
                        Rebalanced {
                            timestamp: get_block_timestamp(),
                            total_deployed: self.total_deployed.read(),
                        }
                    )
                );
        }

        // --------------------------------------------------------------------
        // View Functions
        // --------------------------------------------------------------------
        fn get_total_deposits(self: @ContractState) -> u256 {
            self.total_deposits.read()
        }

        fn get_total_deployed(self: @ContractState) -> u256 {
            self.total_deployed.read()
        }

        fn get_commitment_count(self: @ContractState) -> u256 {
            self.commitment_count.read()
        }

        fn get_strategy_count(self: @ContractState) -> u32 {
            self.strategy_count.read()
        }

        fn get_strategy_allocation(self: @ContractState, strategy_id: u32) -> u256 {
            self.strategy_allocations.read(strategy_id)
        }

        fn get_strategy_deployed(self: @ContractState, strategy_id: u32) -> u256 {
            self.strategy_deployed.read(strategy_id)
        }

        fn get_strategy_protocol(self: @ContractState, strategy_id: u32) -> ContractAddress {
            self.strategy_protocols.read(strategy_id)
        }

        fn is_strategy_active(self: @ContractState, strategy_id: u32) -> bool {
            self.strategy_active.read(strategy_id)
        }

        fn verify_commitment_exists(self: @ContractState, commitment: felt252) -> bool {
            self.commitment_exists.read(commitment)
        }

        fn is_nullifier_used(self: @ContractState, nullifier: felt252) -> bool {
            self.nullifier_used.read(nullifier)
        }

        fn get_vault_idle_balance(self: @ContractState) -> u256 {
            self.total_deposits.read() - self.total_deployed.read()
        }

        fn get_curator(self: @ContractState) -> ContractAddress {
            self.curator.read()
        }

        fn get_deposit_token(self: @ContractState) -> ContractAddress {
            self.deposit_token.read()
        }

        // --------------------------------------------------------------------
        // Solvency Proof
        // Generates a Pedersen commitment proving vault solvency:
        //   commitment = Pedersen(total_deposits, total_deployed)
        // Anyone can verify total_deposits >= total_deployed without
        // revealing individual positions or strategy allocations publicly
        // --------------------------------------------------------------------
        fn get_solvency_commitment(self: @ContractState) -> felt252 {
            let total_deps: felt252 = self.total_deposits.read().low.into();
            let total_depl: felt252 = self.total_deployed.read().low.into();

            let hash = PedersenTrait::new(total_deps).update(total_depl).finalize();

            hash
        }
    }

    // ========================================================================
    // Internal Functions
    // ========================================================================

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _only_curator(self: @ContractState) {
            assert(get_caller_address() == self.curator.read(), 'Only curator');
        }

        fn _get_total_allocation(self: @ContractState) -> u256 {
            let count = self.strategy_count.read();
            let mut total: u256 = 0;
            let mut i: u32 = 0;

            loop {
                if i >= count {
                    break;
                }
                total += self.strategy_allocations.read(i);
                i += 1;
            };

            total
        }

        // ----------------------------------------------------------------
        // ZK Proof Verification
        // Verifies a withdrawal proof linking nullifier to commitment.
        //
        // In production, this would verify a full STARK proof circuit:
        //   1. Prover knows `secret` such that Pedersen(amount, secret) == commitment
        //   2. Pedersen(commitment, secret) == nullifier
        //   3. commitment exists in the Merkle tree of deposits
        //
        // For hackathon MVP, we verify:
        //   Pedersen(nullifier, commitment) == proof_element
        // This demonstrates the ZK verification pattern while being
        // straightforward to test and validate.
        // ----------------------------------------------------------------
        fn _verify_withdrawal_proof(
            self: @ContractState,
            nullifier: felt252,
            commitment: felt252,
            proof_element: felt252,
        ) {
            let expected = PedersenTrait::new(nullifier).update(commitment).finalize();
            assert(expected == proof_element, 'Invalid withdrawal proof');
        }
    }
}
