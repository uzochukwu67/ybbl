use reddio_cairo::privacy_yield_vault::PrivacyYieldVault;
use reddio_cairo::privacy_yield_vault::IPrivacyYieldVaultDispatcher;
use reddio_cairo::privacy_yield_vault::IPrivacyYieldVaultDispatcherTrait;
use reddio_cairo::erc20::ERC20;
use reddio_cairo::erc20::IERC20Dispatcher;
use reddio_cairo::erc20::IERC20DispatcherTrait;

use core::pedersen::PedersenTrait;
use core::hash::HashStateTrait;
use integer::u256_from_felt252;
use traits::Into;
use traits::TryInto;
use result::ResultTrait;
use option::OptionTrait;

use starknet::contract_address_const;
use starknet::contract_address::ContractAddress;
use starknet::testing::{set_caller_address, set_contract_address};
use starknet::syscalls::deploy_syscall;
use starknet::SyscallResultTrait;
use starknet::class_hash::Felt252TryIntoClassHash;

const TOKEN_NAME: felt252 = 'Test WBTC';
const TOKEN_SYMBOL: felt252 = 'tWBTC';
const TOKEN_DECIMALS: u8 = 8_u8;

// ============================================================================
// Helper: Deploy test ERC20 token
// ============================================================================
fn deploy_token(caller: ContractAddress) -> (ContractAddress, IERC20Dispatcher) {
    let mut calldata = array![TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS.into()];
    let (addr, _) = deploy_syscall(
        ERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), false
    )
        .unwrap();
    (addr, IERC20Dispatcher { contract_address: addr })
}

// ============================================================================
// Helper: Deploy Privacy Yield Vault
// ============================================================================
fn deploy_vault() -> (ContractAddress, IPrivacyYieldVaultDispatcher) {
    let calldata = array![];
    let (addr, _) = deploy_syscall(
        PrivacyYieldVault::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), false
    )
        .unwrap();
    (addr, IPrivacyYieldVaultDispatcher { contract_address: addr })
}

// ============================================================================
// Helper: Full setup with token + vault
// ============================================================================
fn setUp() -> (
    ContractAddress,
    ContractAddress,
    IERC20Dispatcher,
    ContractAddress,
    IPrivacyYieldVaultDispatcher,
) {
    let curator = contract_address_const::<1>();
    set_contract_address(curator);

    let (token_addr, token) = deploy_token(curator);
    let (vault_addr, vault) = deploy_vault();

    // Initialize vault with 3 strategies
    vault.initialize(token_addr, curator, 3);

    (curator, token_addr, token, vault_addr, vault)
}

// ============================================================================
// Tests: Initialization
// ============================================================================

#[test]
#[available_gas(5000000)]
fn test_vault_initialize() {
    let (curator, token_addr, _token, _vault_addr, vault) = setUp();

    assert(vault.get_deposit_token() == token_addr, 'Wrong deposit token');
    assert(vault.get_curator() == curator, 'Wrong curator');
    assert(vault.get_strategy_count() == 3, 'Wrong strategy count');
    assert(vault.get_total_deposits() == 0, 'Should have 0 deposits');
    assert(vault.get_total_deployed() == 0, 'Should have 0 deployed');
}

#[test]
#[available_gas(5000000)]
#[should_panic(expected: ('Already initialized', 'ENTRYPOINT_FAILED',))]
fn test_vault_double_initialize() {
    let (curator, token_addr, _token, _vault_addr, vault) = setUp();
    // Try to initialize again - should fail
    vault.initialize(token_addr, curator, 3);
}

#[test]
#[available_gas(5000000)]
#[should_panic(expected: ('Invalid deposit token', 'ENTRYPOINT_FAILED',))]
fn test_vault_initialize_zero_token() {
    let calldata = array![];
    let (addr, _) = deploy_syscall(
        PrivacyYieldVault::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), false
    )
        .unwrap();
    let vault = IPrivacyYieldVaultDispatcher { contract_address: addr };
    let curator = contract_address_const::<1>();
    vault.initialize(contract_address_const::<0>(), curator, 3);
}

// ============================================================================
// Tests: Private Deposit
// ============================================================================

#[test]
#[available_gas(10000000)]
fn test_private_deposit() {
    let (curator, token_addr, token, vault_addr, vault) = setUp();

    // Mint tokens to curator
    let amount: u256 = 100000000; // 1 BTC (8 decimals)
    token.mint(curator, amount);

    // Approve vault to spend tokens
    token.approve(vault_addr, amount);

    // Create commitment: Pedersen(amount_felt, secret)
    let secret: felt252 = 'my_secret_123';
    let amount_felt: felt252 = 100000000;
    let commitment = PedersenTrait::new(amount_felt).update(secret).finalize();

    // Deposit
    vault.deposit_private(amount, commitment);

    // Verify state
    assert(vault.get_total_deposits() == amount, 'Wrong total deposits');
    assert(vault.get_commitment_count() == 1, 'Wrong commitment count');
    assert(vault.verify_commitment_exists(commitment), 'Commitment should exist');
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Amount must be > 0', 'ENTRYPOINT_FAILED',))]
fn test_private_deposit_zero_amount() {
    let (_curator, _token_addr, _token, _vault_addr, vault) = setUp();
    let commitment: felt252 = 'some_commitment';
    vault.deposit_private(0, commitment);
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Invalid commitment', 'ENTRYPOINT_FAILED',))]
fn test_private_deposit_zero_commitment() {
    let (_curator, _token_addr, _token, _vault_addr, vault) = setUp();
    vault.deposit_private(100, 0);
}

// ============================================================================
// Tests: Private Withdrawal
// ============================================================================

#[test]
#[available_gas(15000000)]
fn test_private_withdrawal() {
    let (curator, token_addr, token, vault_addr, vault) = setUp();

    let amount: u256 = 100000000;
    token.mint(curator, amount);
    token.approve(vault_addr, amount);

    // Create and store commitment
    let secret: felt252 = 'withdrawal_secret';
    let amount_felt: felt252 = 100000000;
    let commitment = PedersenTrait::new(amount_felt).update(secret).finalize();
    vault.deposit_private(amount, commitment);

    // Create nullifier and proof
    let nullifier: felt252 = 'unique_nullifier_1';
    let proof_element = PedersenTrait::new(nullifier).update(commitment).finalize();

    // Withdraw
    vault.withdraw_private(amount, nullifier, commitment, proof_element);

    // Verify state
    assert(vault.get_total_deposits() == 0, 'Should have 0 deposits');
    assert(vault.is_nullifier_used(nullifier), 'Nullifier should be used');
}

#[test]
#[available_gas(15000000)]
#[should_panic(expected: ('Nullifier already spent', 'ENTRYPOINT_FAILED',))]
fn test_double_withdrawal() {
    let (curator, _token_addr, token, vault_addr, vault) = setUp();

    let amount: u256 = 100000000;
    token.mint(curator, amount * 2);
    token.approve(vault_addr, amount * 2);

    let secret: felt252 = 'double_spend_secret';
    let amount_felt: felt252 = 100000000;
    let commitment = PedersenTrait::new(amount_felt).update(secret).finalize();
    vault.deposit_private(amount, commitment);

    // Second deposit with different commitment
    let commitment2 = PedersenTrait::new(amount_felt).update('secret2').finalize();
    vault.deposit_private(amount, commitment2);

    // First withdrawal - should succeed
    let nullifier: felt252 = 'nullifier_once';
    let proof = PedersenTrait::new(nullifier).update(commitment).finalize();
    vault.withdraw_private(amount, nullifier, commitment, proof);

    // Second withdrawal with SAME nullifier - should fail
    let proof2 = PedersenTrait::new(nullifier).update(commitment2).finalize();
    vault.withdraw_private(amount, nullifier, commitment2, proof2);
}

#[test]
#[available_gas(15000000)]
#[should_panic(expected: ('Invalid withdrawal proof', 'ENTRYPOINT_FAILED',))]
fn test_invalid_proof() {
    let (curator, _token_addr, token, vault_addr, vault) = setUp();

    let amount: u256 = 100000000;
    token.mint(curator, amount);
    token.approve(vault_addr, amount);

    let commitment = PedersenTrait::new('amount').update('secret').finalize();
    vault.deposit_private(amount, commitment);

    let nullifier: felt252 = 'nullifier';
    let fake_proof: felt252 = 'fake_proof'; // Not the correct Pedersen hash
    vault.withdraw_private(amount, nullifier, commitment, fake_proof);
}

// ============================================================================
// Tests: Strategy Management
// ============================================================================

#[test]
#[available_gas(10000000)]
fn test_set_strategy() {
    let (curator, _token_addr, _token, _vault_addr, vault) = setUp();

    let protocol = contract_address_const::<100>();
    vault.set_strategy(0, protocol, 5000, true); // 50% allocation

    assert(vault.get_strategy_protocol(0) == protocol, 'Wrong protocol');
    assert(vault.get_strategy_allocation(0) == 5000, 'Wrong allocation');
    assert(vault.is_strategy_active(0), 'Should be active');
}

#[test]
#[available_gas(10000000)]
fn test_set_multiple_strategies() {
    let (_curator, _token_addr, _token, _vault_addr, vault) = setUp();

    let vesu = contract_address_const::<100>();
    let ekubo = contract_address_const::<200>();
    let nostra = contract_address_const::<300>();

    vault.set_strategy(0, vesu, 4000, true); // 40% Vesu
    vault.set_strategy(1, ekubo, 3000, true); // 30% Ekubo
    vault.set_strategy(2, nostra, 3000, true); // 30% Nostra

    assert(vault.get_strategy_allocation(0) == 4000, 'Vesu wrong alloc');
    assert(vault.get_strategy_allocation(1) == 3000, 'Ekubo wrong alloc');
    assert(vault.get_strategy_allocation(2) == 3000, 'Nostra wrong alloc');
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Total alloc exceeds 100%', 'ENTRYPOINT_FAILED',))]
fn test_allocation_exceeds_100_percent() {
    let (_curator, _token_addr, _token, _vault_addr, vault) = setUp();

    let protocol1 = contract_address_const::<100>();
    let protocol2 = contract_address_const::<200>();

    vault.set_strategy(0, protocol1, 6000, true); // 60%
    vault.set_strategy(1, protocol2, 5000, true); // 50% - total would be 110%
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Only curator', 'ENTRYPOINT_FAILED',))]
fn test_non_curator_set_strategy() {
    let (_curator, _token_addr, _token, _vault_addr, vault) = setUp();

    // Switch to non-curator address
    let attacker = contract_address_const::<999>();
    set_contract_address(attacker);

    let protocol = contract_address_const::<100>();
    vault.set_strategy(0, protocol, 5000, true);
}

// ============================================================================
// Tests: Solvency Proof
// ============================================================================

#[test]
#[available_gas(10000000)]
fn test_solvency_commitment() {
    let (curator, _token_addr, token, vault_addr, vault) = setUp();

    let amount: u256 = 50000000;
    token.mint(curator, amount);
    token.approve(vault_addr, amount);

    let commitment = PedersenTrait::new('amt').update('sec').finalize();
    vault.deposit_private(amount, commitment);

    // Get solvency commitment - should be Pedersen(total_deposits, total_deployed)
    let solvency = vault.get_solvency_commitment();
    assert(solvency != 0, 'Solvency should be non-zero');

    // Manually compute expected: Pedersen(50000000, 0)
    let expected_deps: felt252 = 50000000;
    let expected_depl: felt252 = 0;
    let expected = PedersenTrait::new(expected_deps).update(expected_depl).finalize();
    assert(solvency == expected, 'Wrong solvency commitment');
}

// ============================================================================
// Tests: View Functions
// ============================================================================

#[test]
#[available_gas(10000000)]
fn test_idle_balance() {
    let (curator, _token_addr, token, vault_addr, vault) = setUp();

    let amount: u256 = 200000000;
    token.mint(curator, amount);
    token.approve(vault_addr, amount);

    let commitment = PedersenTrait::new('a').update('s').finalize();
    vault.deposit_private(amount, commitment);

    // All funds should be idle (nothing deployed)
    assert(vault.get_vault_idle_balance() == amount, 'Wrong idle balance');
}

#[test]
#[available_gas(15000000)]
fn test_multiple_deposits() {
    let (curator, _token_addr, token, vault_addr, vault) = setUp();

    let amount1: u256 = 100000000;
    let amount2: u256 = 200000000;
    token.mint(curator, amount1 + amount2);
    token.approve(vault_addr, amount1 + amount2);

    let c1 = PedersenTrait::new('a1').update('s1').finalize();
    let c2 = PedersenTrait::new('a2').update('s2').finalize();

    vault.deposit_private(amount1, c1);
    vault.deposit_private(amount2, c2);

    assert(vault.get_total_deposits() == amount1 + amount2, 'Wrong total');
    assert(vault.get_commitment_count() == 2, 'Should have 2 commitments');
    assert(vault.verify_commitment_exists(c1), 'c1 should exist');
    assert(vault.verify_commitment_exists(c2), 'c2 should exist');
}
