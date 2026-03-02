use reddio_cairo::strategies::strategy_manager::StrategyManager;
use reddio_cairo::strategies::strategy_manager::IStrategyManagerDispatcher;
use reddio_cairo::strategies::strategy_manager::IStrategyManagerDispatcherTrait;

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

// ============================================================================
// Helper: Deploy Strategy Manager
// ============================================================================
fn deploy_manager() -> (ContractAddress, IStrategyManagerDispatcher) {
    let calldata = array![];
    let (addr, _) = deploy_syscall(
        StrategyManager::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), false
    )
        .unwrap();
    (addr, IStrategyManagerDispatcher { contract_address: addr })
}

fn setUp() -> (ContractAddress, ContractAddress, IStrategyManagerDispatcher) {
    let curator = contract_address_const::<1>();
    set_contract_address(curator);

    let (manager_addr, manager) = deploy_manager();

    let vault = contract_address_const::<10>();
    let token = contract_address_const::<20>();
    let vesu = contract_address_const::<100>();
    let ekubo = contract_address_const::<200>();
    let nostra = contract_address_const::<300>();

    manager.initialize(vault, curator, token, vesu, ekubo, nostra);

    (curator, manager_addr, manager)
}

// ============================================================================
// Tests: Initialization
// ============================================================================

#[test]
#[available_gas(5000000)]
fn test_manager_initialize() {
    let (curator, _manager_addr, manager) = setUp();

    // Check default allocations: 40/30/30
    assert(manager.get_target_allocation(0) == 4000, 'Vesu should be 4000');
    assert(manager.get_target_allocation(1) == 3000, 'Ekubo should be 3000');
    assert(manager.get_target_allocation(2) == 3000, 'Nostra should be 3000');

    // Check adapters are set
    assert(
        manager.get_adapter_address(0) == contract_address_const::<100>(), 'Wrong vesu adapter'
    );
    assert(
        manager.get_adapter_address(1) == contract_address_const::<200>(), 'Wrong ekubo adapter'
    );
    assert(
        manager.get_adapter_address(2) == contract_address_const::<300>(), 'Wrong nostra adapter'
    );
}

#[test]
#[available_gas(5000000)]
#[should_panic(expected: ('Already initialized', 'ENTRYPOINT_FAILED',))]
fn test_manager_double_initialize() {
    let (curator, _manager_addr, manager) = setUp();

    let vault = contract_address_const::<10>();
    let token = contract_address_const::<20>();
    let vesu = contract_address_const::<100>();
    let ekubo = contract_address_const::<200>();
    let nostra = contract_address_const::<300>();

    manager.initialize(vault, curator, token, vesu, ekubo, nostra);
}

// ============================================================================
// Tests: Allocation Management
// ============================================================================

#[test]
#[available_gas(5000000)]
fn test_set_allocations() {
    let (_curator, _manager_addr, manager) = setUp();

    // Change to 50/25/25
    manager.set_target_allocations(5000, 2500, 2500);

    assert(manager.get_target_allocation(0) == 5000, 'Vesu should be 5000');
    assert(manager.get_target_allocation(1) == 2500, 'Ekubo should be 2500');
    assert(manager.get_target_allocation(2) == 2500, 'Nostra should be 2500');
}

#[test]
#[available_gas(5000000)]
#[should_panic(expected: ('Total exceeds 100%', 'ENTRYPOINT_FAILED',))]
fn test_allocations_exceed_100() {
    let (_curator, _manager_addr, manager) = setUp();

    manager.set_target_allocations(5000, 3000, 3000); // 110%
}

#[test]
#[available_gas(5000000)]
fn test_partial_allocation() {
    let (_curator, _manager_addr, manager) = setUp();

    // Only allocate 60%, keep 40% idle
    manager.set_target_allocations(3000, 2000, 1000);

    assert(manager.get_target_allocation(0) == 3000, 'Vesu should be 3000');
    assert(manager.get_target_allocation(1) == 2000, 'Ekubo should be 2000');
    assert(manager.get_target_allocation(2) == 1000, 'Nostra should be 1000');
}

// ============================================================================
// Tests: Pause/Unpause
// ============================================================================

#[test]
#[available_gas(5000000)]
fn test_pause_strategy() {
    let (_curator, _manager_addr, manager) = setUp();

    assert(!manager.is_strategy_paused(0), 'Should not be paused');

    manager.pause_strategy(0);
    assert(manager.is_strategy_paused(0), 'Should be paused');

    manager.unpause_strategy(0);
    assert(!manager.is_strategy_paused(0), 'Should be unpaused');
}

#[test]
#[available_gas(5000000)]
#[should_panic(expected: ('Only curator', 'ENTRYPOINT_FAILED',))]
fn test_non_curator_pause() {
    let (_curator, _manager_addr, manager) = setUp();

    let attacker = contract_address_const::<999>();
    set_contract_address(attacker);

    manager.pause_strategy(0);
}

#[test]
#[available_gas(5000000)]
#[should_panic(expected: ('Only curator', 'ENTRYPOINT_FAILED',))]
fn test_non_curator_set_allocations() {
    let (_curator, _manager_addr, manager) = setUp();

    let attacker = contract_address_const::<999>();
    set_contract_address(attacker);

    manager.set_target_allocations(5000, 2500, 2500);
}

// ============================================================================
// Tests: Invalid Strategy ID
// ============================================================================

#[test]
#[available_gas(5000000)]
fn test_invalid_strategy_id_returns_zero() {
    let (_curator, _manager_addr, manager) = setUp();

    // Strategy ID 99 doesn't exist - should return 0 allocation
    assert(manager.get_target_allocation(99) == 0, 'Should return 0');

    // Should return zero address for invalid adapter
    assert(
        manager.get_adapter_address(99) == contract_address_const::<0>(), 'Should return zero addr'
    );

    // Invalid strategy should be "paused" (true)
    assert(manager.is_strategy_paused(99), 'Invalid should be paused');
}
