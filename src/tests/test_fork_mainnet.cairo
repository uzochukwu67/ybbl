use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::Felt252TryIntoContractAddress;
use array::ArrayTrait;
use traits::Into;
use traits::TryInto;
use result::ResultTrait;
use option::OptionTrait;
use serde::Serde;
use core::pedersen::PedersenTrait;
use core::hash::HashStateTrait;

use snforge_std::{
    declare, ContractClassTrait,
    start_prank, stop_prank,
    start_warp, stop_warp,
    start_mock_call, stop_mock_call,
    BlockTag, BlockId,
};

use reddio_cairo::privacy_yield_vault::IPrivacyYieldVaultDispatcher;
use reddio_cairo::privacy_yield_vault::IPrivacyYieldVaultDispatcherTrait;
use reddio_cairo::erc20::IERC20Dispatcher;
use reddio_cairo::erc20::IERC20DispatcherTrait;

// ============================================================================
// Starknet Mainnet Token Addresses
// ============================================================================
fn ETH_MAINNET() -> ContractAddress {
    contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>()
}

fn USDC_MAINNET() -> ContractAddress {
    contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>()
}

fn WBTC_MAINNET() -> ContractAddress {
    contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>()
}

fn CURATOR() -> ContractAddress {
    contract_address_const::<0x1234>()
}

fn USER() -> ContractAddress {
    contract_address_const::<0xBEEF>()
}

// ============================================================================
// ERC20 Interface for reading mainnet token state
// ============================================================================
#[starknet::interface]
trait IMainnetERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

// ============================================================================
// FORK TEST GROUP 1: Read real mainnet ERC20 token state
// Verifies we can fork Starknet mainnet and read actual on-chain state.
// ============================================================================

#[test]
#[fork(url: "https://free-rpc.nethermind.io/mainnet-juno/v0_7", block_id: BlockId::Tag(BlockTag::Latest))]
fn test_fork_read_eth_token() {
    let eth = IMainnetERC20Dispatcher { contract_address: ETH_MAINNET() };

    let name = eth.name();
    let symbol = eth.symbol();
    let decimals = eth.decimals();
    let supply = eth.total_supply();

    // ETH on Starknet should have known properties
    assert(name == 'Ether', 'ETH name wrong');
    assert(symbol == 'ETH', 'ETH symbol wrong');
    assert(decimals == 18, 'ETH decimals wrong');
    assert(supply > 0, 'ETH supply should be > 0');
}

#[test]
#[fork(url: "https://free-rpc.nethermind.io/mainnet-juno/v0_7", block_id: BlockId::Tag(BlockTag::Latest))]
fn test_fork_read_usdc_token() {
    let usdc = IMainnetERC20Dispatcher { contract_address: USDC_MAINNET() };

    let decimals = usdc.decimals();
    let supply = usdc.total_supply();

    assert(decimals == 6, 'USDC decimals wrong');
    assert(supply > 0, 'USDC supply should be > 0');
}

#[test]
#[fork(url: "https://free-rpc.nethermind.io/mainnet-juno/v0_7", block_id: BlockId::Tag(BlockTag::Latest))]
fn test_fork_read_wbtc_token() {
    let wbtc = IMainnetERC20Dispatcher { contract_address: WBTC_MAINNET() };

    let decimals = wbtc.decimals();
    let supply = wbtc.total_supply();

    assert(decimals == 8, 'WBTC decimals wrong');
    assert(supply > 0, 'WBTC supply should be > 0');
}

// ============================================================================
// FORK TEST GROUP 2: Check real whale balances on mainnet
// Tests that actual high-TVL accounts have balances (proves fork is working)
// ============================================================================

#[test]
#[fork(url: "https://free-rpc.nethermind.io/mainnet-juno/v0_7", block_id: BlockId::Tag(BlockTag::Latest))]
fn test_fork_eth_whale_balance() {
    let eth = IMainnetERC20Dispatcher { contract_address: ETH_MAINNET() };

    // Starknet bridge contract holds significant ETH
    // StarkGate ETH Bridge:
    let bridge = contract_address_const::<0x073314940630fd6dcda0d772d4c972c4e0a9946bef9dabf4ef84eda8ef542b82>();
    let balance = eth.balance_of(bridge);

    // The bridge should hold a non-trivial amount of ETH
    assert(balance > 0, 'Bridge should have ETH');
}

// ============================================================================
// FORK TEST GROUP 3: Deploy Privacy Vault on fork and interact with
// real mainnet token state
// ============================================================================

#[test]
#[fork(url: "https://free-rpc.nethermind.io/mainnet-juno/v0_7", block_id: BlockId::Tag(BlockTag::Latest))]
fn test_fork_deploy_vault_with_mainnet_eth() {
    // Deploy our vault contract on the fork
    let vault_contract = declare('PrivacyYieldVault');
    let vault_addr = vault_contract.deploy(@array![]).unwrap();
    let vault = IPrivacyYieldVaultDispatcher { contract_address: vault_addr };

    // Initialize with ETH as deposit token
    start_prank(vault_addr, CURATOR());
    vault.initialize(ETH_MAINNET(), CURATOR(), 3);
    stop_prank(vault_addr);

    // Verify vault configuration
    assert(vault.get_deposit_token() == ETH_MAINNET(), 'Wrong deposit token');
    assert(vault.get_curator() == CURATOR(), 'Wrong curator');
    assert(vault.get_strategy_count() == 3, 'Wrong strategy count');
    assert(vault.get_total_deposits() == 0, 'Should have 0 deposits');
}

#[test]
#[fork(url: "https://free-rpc.nethermind.io/mainnet-juno/v0_7", block_id: BlockId::Tag(BlockTag::Latest))]
fn test_fork_vault_strategy_config_with_real_protocols() {
    // Deploy vault
    let vault_contract = declare('PrivacyYieldVault');
    let vault_addr = vault_contract.deploy(@array![]).unwrap();
    let vault = IPrivacyYieldVaultDispatcher { contract_address: vault_addr };

    start_prank(vault_addr, CURATOR());
    vault.initialize(ETH_MAINNET(), CURATOR(), 3);

    // Configure strategies with addresses that exist on mainnet
    // These are representative DeFi protocol addresses
    let vesu_pool = contract_address_const::<0x02545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148571f7>();
    let ekubo_core = contract_address_const::<0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b>();
    let nostra_main = contract_address_const::<0x04c0a5193d58f74fbace4b74dcf65481e734ed1714121bdc571da345540efa05>();

    vault.set_strategy(0, vesu_pool, 4000, true);    // 40% Vesu
    vault.set_strategy(1, ekubo_core, 3000, true);   // 30% Ekubo
    vault.set_strategy(2, nostra_main, 3000, true);  // 30% Nostra
    stop_prank(vault_addr);

    // Verify on-chain
    assert(vault.get_strategy_protocol(0) == vesu_pool, 'Vesu addr wrong');
    assert(vault.get_strategy_protocol(1) == ekubo_core, 'Ekubo addr wrong');
    assert(vault.get_strategy_protocol(2) == nostra_main, 'Nostra addr wrong');
    assert(vault.is_strategy_active(0), 'Vesu inactive');
    assert(vault.is_strategy_active(1), 'Ekubo inactive');
    assert(vault.is_strategy_active(2), 'Nostra inactive');

    // Solvency proof should work
    let solvency = vault.get_solvency_commitment();
    let expected = PedersenTrait::new(0).update(0).finalize();
    assert(solvency == expected, 'Wrong solvency (0 deposits)');
}

// ============================================================================
// FORK TEST GROUP 4: Deploy Strategy Manager on fork
// ============================================================================

use reddio_cairo::strategies::strategy_manager::IStrategyManagerDispatcher;
use reddio_cairo::strategies::strategy_manager::IStrategyManagerDispatcherTrait;

#[test]
#[fork(url: "https://free-rpc.nethermind.io/mainnet-juno/v0_7", block_id: BlockId::Tag(BlockTag::Latest))]
fn test_fork_strategy_manager_deploy_and_configure() {
    let manager_contract = declare('StrategyManager');
    let mgr_addr = manager_contract.deploy(@array![]).unwrap();
    let manager = IStrategyManagerDispatcher { contract_address: mgr_addr };

    let vault_addr = contract_address_const::<0xAAAA>();
    let vesu_adapter = contract_address_const::<0x100>();
    let ekubo_adapter = contract_address_const::<0x200>();
    let nostra_adapter = contract_address_const::<0x300>();

    start_prank(mgr_addr, CURATOR());
    manager.initialize(
        vault_addr, CURATOR(), ETH_MAINNET(), vesu_adapter, ekubo_adapter, nostra_adapter,
    );
    stop_prank(mgr_addr);

    // Verify defaults on fork
    assert(manager.get_target_allocation(0) == 4000, 'Vesu default 40%');
    assert(manager.get_target_allocation(1) == 3000, 'Ekubo default 30%');
    assert(manager.get_target_allocation(2) == 3000, 'Nostra default 30%');

    // Reconfigure
    start_prank(mgr_addr, CURATOR());
    manager.set_target_allocations(5000, 3000, 2000); // 50/30/20
    stop_prank(mgr_addr);

    assert(manager.get_target_allocation(0) == 5000, 'Vesu new 50%');
    assert(manager.get_target_allocation(2) == 2000, 'Nostra new 20%');
}

#[test]
#[fork(url: "https://free-rpc.nethermind.io/mainnet-juno/v0_7", block_id: BlockId::Tag(BlockTag::Latest))]
fn test_fork_strategy_manager_emergency_flow() {
    let manager_contract = declare('StrategyManager');
    let mgr_addr = manager_contract.deploy(@array![]).unwrap();
    let manager = IStrategyManagerDispatcher { contract_address: mgr_addr };

    let vault_addr = contract_address_const::<0xAAAA>();
    let vesu_adapter = contract_address_const::<0x100>();
    let ekubo_adapter = contract_address_const::<0x200>();
    let nostra_adapter = contract_address_const::<0x300>();

    start_prank(mgr_addr, CURATOR());
    manager.initialize(
        vault_addr, CURATOR(), ETH_MAINNET(), vesu_adapter, ekubo_adapter, nostra_adapter,
    );
    stop_prank(mgr_addr);

    // Mock adapters for emergency withdraw
    start_mock_call(vesu_adapter, 'emergency_withdraw', 5000_u256);
    start_mock_call(ekubo_adapter, 'emergency_withdraw', 3000_u256);
    start_mock_call(nostra_adapter, 'emergency_withdraw', 2000_u256);

    start_prank(mgr_addr, CURATOR());
    let recovered = manager.emergency_withdraw_all();
    stop_prank(mgr_addr);

    assert(recovered == 10000, 'Wrong recovery amount');
    assert(manager.is_strategy_paused(0), 'Vesu should be paused');
    assert(manager.is_strategy_paused(1), 'Ekubo should be paused');
    assert(manager.is_strategy_paused(2), 'Nostra should be paused');

    stop_mock_call(vesu_adapter, 'emergency_withdraw');
    stop_mock_call(ekubo_adapter, 'emergency_withdraw');
    stop_mock_call(nostra_adapter, 'emergency_withdraw');
}

// ============================================================================
// FORK TEST GROUP 5: Full end-to-end vault lifecycle on fork
// ============================================================================

#[test]
#[fork(url: "https://free-rpc.nethermind.io/mainnet-juno/v0_7", block_id: BlockId::Tag(BlockTag::Latest))]
fn test_fork_full_vault_lifecycle() {
    // Deploy vault
    let vault_contract = declare('PrivacyYieldVault');
    let vault_addr = vault_contract.deploy(@array![]).unwrap();
    let vault = IPrivacyYieldVaultDispatcher { contract_address: vault_addr };

    // Deploy a test ERC20 (since we can't mint real ETH)
    let token_contract = declare('ERC20');
    let token_addr = token_contract.deploy(@array!['Test ETH', 'tETH', 18]).unwrap();
    let token = IERC20Dispatcher { contract_address: token_addr };

    // Initialize vault with test token
    start_prank(vault_addr, CURATOR());
    vault.initialize(token_addr, CURATOR(), 3);
    stop_prank(vault_addr);

    // Mint tokens to user
    token.mint(USER(), 10000000000000000000); // 10 tETH

    // User approves and deposits privately
    start_prank(token_addr, USER());
    token.approve(vault_addr, 10000000000000000000);
    stop_prank(token_addr);

    let deposit_amount: u256 = 5000000000000000000; // 5 tETH
    let secret: felt252 = 'mainnet_fork_secret_42';
    let commitment = PedersenTrait::new(5000000000000000000).update(secret).finalize();

    start_prank(vault_addr, USER());
    vault.deposit_private(deposit_amount, commitment);
    stop_prank(vault_addr);

    // Verify deposit
    assert(vault.get_total_deposits() == deposit_amount, 'Wrong deposit on fork');
    assert(vault.verify_commitment_exists(commitment), 'Commitment not stored');

    // Configure strategies
    let vesu = contract_address_const::<0x100>();
    let ekubo = contract_address_const::<0x200>();
    let nostra = contract_address_const::<0x300>();

    start_prank(vault_addr, CURATOR());
    vault.set_strategy(0, vesu, 4000, true);
    vault.set_strategy(1, ekubo, 3000, true);
    vault.set_strategy(2, nostra, 3000, true);
    stop_prank(vault_addr);

    // Deploy 2 tETH to Vesu strategy
    start_mock_call(token_addr, 'transfer', true);
    start_prank(vault_addr, CURATOR());
    vault.deploy_to_strategy(0, 2000000000000000000);
    stop_prank(vault_addr);
    stop_mock_call(token_addr, 'transfer');

    assert(vault.get_strategy_deployed(0) == 2000000000000000000, 'Wrong Vesu deployed');
    assert(vault.get_total_deployed() == 2000000000000000000, 'Wrong total deployed');
    assert(vault.get_vault_idle_balance() == 3000000000000000000, 'Wrong idle');

    // Verify solvency proof reflects deployed state
    let solvency = vault.get_solvency_commitment();
    let expected = PedersenTrait::new(5000000000000000000).update(2000000000000000000).finalize();
    assert(solvency == expected, 'Wrong solvency after deploy');

    // Withdraw privately (from idle balance)
    let withdraw_amount: u256 = 1000000000000000000; // 1 tETH
    let nullifier: felt252 = 'fork_nullifier_unique';
    let proof = PedersenTrait::new(nullifier).update(commitment).finalize();

    // Need to unmock transfer for the actual withdrawal
    start_mock_call(token_addr, 'transfer', true);
    start_prank(vault_addr, USER());
    vault.withdraw_private(withdraw_amount, nullifier, commitment, proof);
    stop_prank(vault_addr);
    stop_mock_call(token_addr, 'transfer');

    // Verify final state
    assert(vault.get_total_deposits() == 4000000000000000000, 'Wrong final deposits');
    assert(vault.is_nullifier_used(nullifier), 'Nullifier not marked');
}
