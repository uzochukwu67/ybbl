use starknet::ContractAddress;

// ============================================================================
// Common ERC20 Interface
// ============================================================================

#[starknet::interface]
trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(
        self: @TContractState, owner: ContractAddress, spender: ContractAddress
    ) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

// ============================================================================
// Strategy Adapter Interface
// All protocol strategy adapters must implement this interface
// ============================================================================

#[starknet::interface]
trait IStrategyAdapter<TContractState> {
    /// Deposit tokens into the underlying protocol
    fn deposit(ref self: TContractState, amount: u256);

    /// Withdraw tokens from the underlying protocol back to the vault
    fn withdraw(ref self: TContractState, amount: u256);

    /// Harvest any earned yield and return it to the vault
    fn harvest(ref self: TContractState) -> u256;

    /// Get the total balance deployed in this strategy (principal + yield)
    fn get_total_balance(self: @TContractState) -> u256;

    /// Get the amount of unharvested yield
    fn get_pending_yield(self: @TContractState) -> u256;

    /// Get the underlying protocol address
    fn get_protocol(self: @TContractState) -> ContractAddress;

    /// Get the vault address that owns this strategy
    fn get_vault(self: @TContractState) -> ContractAddress;

    /// Emergency withdraw all funds back to vault (curator only)
    fn emergency_withdraw(ref self: TContractState) -> u256;
}

// ============================================================================
// Vesu Lending Protocol Interface
// Vesu is a lending protocol on Starknet - users supply assets to earn yield
// ============================================================================

#[starknet::interface]
trait IVesuPool<TContractState> {
    /// Supply assets to a Vesu lending pool
    fn deposit(ref self: TContractState, asset: ContractAddress, amount: u256);

    /// Withdraw assets from a Vesu lending pool
    fn withdraw(ref self: TContractState, asset: ContractAddress, amount: u256);

    /// Get the current supply balance for an account
    fn get_deposit_balance(
        self: @TContractState, asset: ContractAddress, account: ContractAddress
    ) -> u256;
}

// ============================================================================
// Ekubo DEX Interface
// Ekubo is a concentrated liquidity DEX on Starknet
// ============================================================================

#[starknet::interface]
trait IEkuboRouter<TContractState> {
    /// Add liquidity to an Ekubo pool
    fn add_liquidity(
        ref self: TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        amount_a: u256,
        amount_b: u256,
        min_liquidity: u256,
    ) -> u256; // returns liquidity minted

    /// Remove liquidity from an Ekubo pool
    fn remove_liquidity(
        ref self: TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        liquidity: u256,
        min_amount_a: u256,
        min_amount_b: u256,
    );

    /// Get position value in terms of underlying tokens
    fn get_position_value(
        self: @TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        owner: ContractAddress,
    ) -> u256;
}

// ============================================================================
// Nostra Money Market Interface
// Nostra is a lending/borrowing protocol on Starknet
// ============================================================================

#[starknet::interface]
trait INostraMarket<TContractState> {
    /// Supply assets to Nostra money market
    fn supply(ref self: TContractState, asset: ContractAddress, amount: u256);

    /// Withdraw assets from Nostra money market
    fn withdraw(ref self: TContractState, asset: ContractAddress, amount: u256);

    /// Get the current supply balance for an account
    fn get_supply_balance(
        self: @TContractState, asset: ContractAddress, account: ContractAddress
    ) -> u256;
}
