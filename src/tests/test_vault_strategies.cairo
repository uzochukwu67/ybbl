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
};

use reddio_cairo::privacy_yield_vault::IPrivacyYieldVaultDispatcher;
use reddio_cairo::privacy_yield_vault::IPrivacyYieldVaultDispatcherTrait;
use reddio_cairo::erc20::IERC20Dispatcher;
use reddio_cairo::erc20::IERC20DispatcherTrait;

// ============================================================================
// Known Starknet Mainnet Addresses
// ============================================================================
fn ETH_ADDRESS() -> ContractAddress {
    contract_address_const::<0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>()
}

fn USDC_ADDRESS() -> ContractAddress {
    contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>()
}

fn WBTC_ADDRESS() -> ContractAddress {
    contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>()
}

fn CURATOR() -> ContractAddress {
    contract_address_const::<0x1234>()
}

fn USER_1() -> ContractAddress {
    contract_address_const::<0xBEEF>()
}

fn USER_2() -> ContractAddress {
    contract_address_const::<0xCAFE>()
}

// ============================================================================
// Helper: Deploy ERC20 + Vault for local tests
// ============================================================================
fn deploy_erc20() -> (ContractAddress, IERC20Dispatcher) {
    let contract = declare('ERC20');
    let mut calldata = array!['Test Token', 'TT', 18_felt252];
    let addr = contract.deploy(@calldata).unwrap();
    (addr, IERC20Dispatcher { contract_address: addr })
}

fn deploy_vault() -> (ContractAddress, IPrivacyYieldVaultDispatcher) {
    let contract = declare('PrivacyYieldVault');
    let calldata = array![];
    let addr = contract.deploy(@calldata).unwrap();
    (addr, IPrivacyYieldVaultDispatcher { contract_address: addr })
}

fn full_setup() -> (
    ContractAddress,
    IERC20Dispatcher,
    ContractAddress,
    IPrivacyYieldVaultDispatcher,
) {
    let (token_addr, token) = deploy_erc20();
    let (vault_addr, vault) = deploy_vault();

    // Initialize vault as curator
    start_prank(vault_addr, CURATOR());
    vault.initialize(token_addr, CURATOR(), 3);
    stop_prank(vault_addr);

    (token_addr, token, vault_addr, vault)
}

// ============================================================================
// TEST GROUP 1: Privacy Vault - Core Deposit/Withdraw
// ============================================================================

#[test]
fn test_vault_init_and_deposit() {
    let (token_addr, token, vault_addr, vault) = full_setup();

    // Mint tokens to user
    token.mint(USER_1(), 1000000);

    // User approves vault
    start_prank(token_addr, USER_1());
    token.approve(vault_addr, 1000000);
    stop_prank(token_addr);

    // Create commitment
    let secret: felt252 = 'deposit_secret_1';
    let amount_felt: felt252 = 1000000;
    let commitment = PedersenTrait::new(amount_felt).update(secret).finalize();

    // User deposits
    start_prank(vault_addr, USER_1());
    vault.deposit_private(1000000, commitment);
    stop_prank(vault_addr);

    // Verify
    assert(vault.get_total_deposits() == 1000000, 'Wrong deposits');
    assert(vault.get_commitment_count() == 1, 'Wrong commitment count');
    assert(vault.verify_commitment_exists(commitment), 'Commitment missing');
    assert(vault.get_vault_idle_balance() == 1000000, 'Wrong idle balance');
}

#[test]
fn test_vault_deposit_and_withdraw_cycle() {
    let (token_addr, token, vault_addr, vault) = full_setup();

    let amount: u256 = 500000;
    token.mint(USER_1(), amount);

    start_prank(token_addr, USER_1());
    token.approve(vault_addr, amount);
    stop_prank(token_addr);

    // Deposit with commitment
    let secret: felt252 = 'cycle_secret';
    let commitment = PedersenTrait::new(500000).update(secret).finalize();

    start_prank(vault_addr, USER_1());
    vault.deposit_private(amount, commitment);
    stop_prank(vault_addr);

    assert(vault.get_total_deposits() == amount, 'Deposit failed');

    // Withdraw with nullifier
    let nullifier: felt252 = 'unique_null_1';
    let proof = PedersenTrait::new(nullifier).update(commitment).finalize();

    start_prank(vault_addr, USER_1());
    vault.withdraw_private(amount, nullifier, commitment, proof);
    stop_prank(vault_addr);

    assert(vault.get_total_deposits() == 0, 'Withdraw failed');
    assert(vault.is_nullifier_used(nullifier), 'Nullifier not marked');

    // User got tokens back
    assert(token.balance_of(USER_1()) == amount, 'Tokens not returned');
}

#[test]
#[should_panic(expected: ('Nullifier already spent', ))]
fn test_double_spend_prevention() {
    let (token_addr, token, vault_addr, vault) = full_setup();

    token.mint(USER_1(), 1000000);

    start_prank(token_addr, USER_1());
    token.approve(vault_addr, 1000000);
    stop_prank(token_addr);

    let c1 = PedersenTrait::new(500000).update('s1').finalize();
    let c2 = PedersenTrait::new(500000).update('s2').finalize();

    start_prank(vault_addr, USER_1());
    vault.deposit_private(500000, c1);
    vault.deposit_private(500000, c2);
    stop_prank(vault_addr);

    let nullifier: felt252 = 'reused_null';

    // First withdrawal - ok
    let proof1 = PedersenTrait::new(nullifier).update(c1).finalize();
    start_prank(vault_addr, USER_1());
    vault.withdraw_private(500000, nullifier, c1, proof1);

    // Second withdrawal same nullifier - should fail
    let proof2 = PedersenTrait::new(nullifier).update(c2).finalize();
    vault.withdraw_private(500000, nullifier, c2, proof2);
    stop_prank(vault_addr);
}

#[test]
#[should_panic(expected: ('Invalid withdrawal proof', ))]
fn test_invalid_proof_rejected() {
    let (token_addr, token, vault_addr, vault) = full_setup();

    token.mint(USER_1(), 500000);

    start_prank(token_addr, USER_1());
    token.approve(vault_addr, 500000);
    stop_prank(token_addr);

    let commitment = PedersenTrait::new(500000).update('secret').finalize();

    start_prank(vault_addr, USER_1());
    vault.deposit_private(500000, commitment);

    // Try with a fake proof
    vault.withdraw_private(500000, 'null', commitment, 'fake_proof');
    stop_prank(vault_addr);
}

// ============================================================================
// TEST GROUP 2: Strategy Configuration
// ============================================================================

#[test]
fn test_strategy_setup_three_protocols() {
    let (_token_addr, _token, vault_addr, vault) = full_setup();

    let vesu = contract_address_const::<0x2545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148571f7>();
    let ekubo = contract_address_const::<0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b>();
    let nostra = contract_address_const::<0x040b091cb020d91f4a4b34396946b4d4e2a450dbd9f6639571c6f036dd7148>();

    start_prank(vault_addr, CURATOR());
    vault.set_strategy(0, vesu, 4000, true);    // 40% Vesu
    vault.set_strategy(1, ekubo, 3000, true);   // 30% Ekubo
    vault.set_strategy(2, nostra, 3000, true);  // 30% Nostra
    stop_prank(vault_addr);

    assert(vault.get_strategy_protocol(0) == vesu, 'Wrong Vesu addr');
    assert(vault.get_strategy_protocol(1) == ekubo, 'Wrong Ekubo addr');
    assert(vault.get_strategy_protocol(2) == nostra, 'Wrong Nostra addr');

    assert(vault.get_strategy_allocation(0) == 4000, 'Vesu alloc wrong');
    assert(vault.get_strategy_allocation(1) == 3000, 'Ekubo alloc wrong');
    assert(vault.get_strategy_allocation(2) == 3000, 'Nostra alloc wrong');

    assert(vault.is_strategy_active(0), 'Vesu not active');
    assert(vault.is_strategy_active(1), 'Ekubo not active');
    assert(vault.is_strategy_active(2), 'Nostra not active');
}

#[test]
#[should_panic(expected: ('Total alloc exceeds 100%', ))]
fn test_overallocation_rejected() {
    let (_token_addr, _token, vault_addr, vault) = full_setup();

    start_prank(vault_addr, CURATOR());
    vault.set_strategy(0, contract_address_const::<100>(), 7000, true); // 70%
    vault.set_strategy(1, contract_address_const::<200>(), 4000, true); // 40% -> 110% total
    stop_prank(vault_addr);
}

#[test]
#[should_panic(expected: ('Only curator', ))]
fn test_non_curator_cannot_set_strategy() {
    let (_token_addr, _token, vault_addr, vault) = full_setup();

    start_prank(vault_addr, USER_1()); // Not the curator
    vault.set_strategy(0, contract_address_const::<100>(), 5000, true);
    stop_prank(vault_addr);
}

// ============================================================================
// TEST GROUP 3: Deploy to Strategy (with mocked protocol)
// ============================================================================

#[test]
fn test_deploy_to_strategy() {
    let (token_addr, token, vault_addr, vault) = full_setup();

    let protocol = contract_address_const::<0xDEAD>();

    // Setup strategy
    start_prank(vault_addr, CURATOR());
    vault.set_strategy(0, protocol, 5000, true);
    stop_prank(vault_addr);

    // Deposit funds
    let amount: u256 = 1000000;
    token.mint(USER_1(), amount);

    start_prank(token_addr, USER_1());
    token.approve(vault_addr, amount);
    stop_prank(token_addr);

    let commitment = PedersenTrait::new(1000000).update('deploy_test').finalize();

    start_prank(vault_addr, USER_1());
    vault.deposit_private(amount, commitment);
    stop_prank(vault_addr);

    // Mock the protocol's transfer acceptance
    // (The vault will try to transfer tokens to the protocol address)
    start_mock_call(token_addr, 'transfer', true);

    // Curator deploys 500k to strategy 0
    start_prank(vault_addr, CURATOR());
    vault.deploy_to_strategy(0, 500000);
    stop_prank(vault_addr);

    assert(vault.get_strategy_deployed(0) == 500000, 'Wrong deployed amt');
    assert(vault.get_total_deployed() == 500000, 'Wrong total deployed');
}

// ============================================================================
// TEST GROUP 4: Solvency Proof
// ============================================================================

#[test]
fn test_solvency_proof_matches() {
    let (token_addr, token, vault_addr, vault) = full_setup();

    token.mint(USER_1(), 750000);

    start_prank(token_addr, USER_1());
    token.approve(vault_addr, 750000);
    stop_prank(token_addr);

    let commitment = PedersenTrait::new(750000).update('solvency_sec').finalize();

    start_prank(vault_addr, USER_1());
    vault.deposit_private(750000, commitment);
    stop_prank(vault_addr);

    // Solvency commitment = Pedersen(total_deposits, total_deployed)
    let solvency = vault.get_solvency_commitment();
    let expected = PedersenTrait::new(750000).update(0).finalize();
    assert(solvency == expected, 'Wrong solvency proof');
}

// ============================================================================
// TEST GROUP 5: Multiple Users Privacy Isolation
// ============================================================================

#[test]
fn test_multiple_users_independent_deposits() {
    let (token_addr, token, vault_addr, vault) = full_setup();

    // Mint to both users
    token.mint(USER_1(), 300000);
    token.mint(USER_2(), 700000);

    // User 1 approves and deposits
    start_prank(token_addr, USER_1());
    token.approve(vault_addr, 300000);
    stop_prank(token_addr);

    let c1 = PedersenTrait::new(300000).update('user1_secret').finalize();
    start_prank(vault_addr, USER_1());
    vault.deposit_private(300000, c1);
    stop_prank(vault_addr);

    // User 2 approves and deposits
    start_prank(token_addr, USER_2());
    token.approve(vault_addr, 700000);
    stop_prank(token_addr);

    let c2 = PedersenTrait::new(700000).update('user2_secret').finalize();
    start_prank(vault_addr, USER_2());
    vault.deposit_private(700000, c2);
    stop_prank(vault_addr);

    // Total should be combined, but commitments are separate
    assert(vault.get_total_deposits() == 1000000, 'Wrong total');
    assert(vault.get_commitment_count() == 2, 'Wrong count');
    assert(vault.verify_commitment_exists(c1), 'c1 missing');
    assert(vault.verify_commitment_exists(c2), 'c2 missing');

    // User 1 withdraws - only their funds
    let n1: felt252 = 'null_user1';
    let p1 = PedersenTrait::new(n1).update(c1).finalize();
    start_prank(vault_addr, USER_1());
    vault.withdraw_private(300000, n1, c1, p1);
    stop_prank(vault_addr);

    // User 2's deposit is unaffected
    assert(vault.get_total_deposits() == 700000, 'User2 funds affected');
    assert(token.balance_of(USER_1()) == 300000, 'User1 not refunded');
}

// ============================================================================
// TEST GROUP 6: Time-based yield simulation
// ============================================================================

#[test]
fn test_warp_time_for_yield() {
    let (token_addr, token, vault_addr, vault) = full_setup();

    token.mint(USER_1(), 1000000);

    start_prank(token_addr, USER_1());
    token.approve(vault_addr, 1000000);
    stop_prank(token_addr);

    // Set initial time
    start_warp(vault_addr, 1000000);

    let commitment = PedersenTrait::new(1000000).update('time_secret').finalize();
    start_prank(vault_addr, USER_1());
    vault.deposit_private(1000000, commitment);
    stop_prank(vault_addr);

    // Fast forward 30 days (simulating yield accrual time)
    start_warp(vault_addr, 1000000 + 86400 * 30);

    // Vault still has the same deposits (yield is tracked per-strategy)
    assert(vault.get_total_deposits() == 1000000, 'Deposits unchanged');

    stop_warp(vault_addr);
}
