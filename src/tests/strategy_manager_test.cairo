use reddio_cairo::strategies::strategy_manager::IStrategyManagerDispatcher;
use reddio_cairo::strategies::strategy_manager::IStrategyManagerDispatcherTrait;

use traits::Into;
use traits::TryInto;
use result::ResultTrait;
use option::OptionTrait;

use starknet::contract_address_const;
use starknet::contract_address::ContractAddress;

use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank};

// ============================================================================
// Helper: Deploy Strategy Manager
// ============================================================================
fn deploy_manager() -> (ContractAddress, IStrategyManagerDispatcher) {
    let contract = declare('StrategyManager');
    let addr = contract.deploy(@array![]).unwrap();
    (addr, IStrategyManagerDispatcher { contract_address: addr })
}

fn setUp() -> (ContractAddress, ContractAddress, IStrategyManagerDispatcher) {
    let curator = contract_address_const::<1>();

    let (manager_addr, manager) = deploy_manager();

    let vault = contract_address_const::<10>();
    let token = contract_address_const::<20>();
    let vesu = contract_address_const::<100>();
    let ekubo = contract_address_const::<200>();
    let nostra = contract_address_const::<300>();

    start_prank(manager_addr, curator);
    manager.initialize(vault, curator, token, vesu, ekubo, nostra);
    stop_prank(manager_addr);

    (curator, manager_addr, manager)
}

// ============================================================================
// Tests: Initialization
// ============================================================================

#[test]
fn test_manager_initialize() {
    let (_curator, _manager_addr, manager) = setUp();

    assert(manager.get_target_allocation(0) == 4000, 'Vesu should be 4000');
    assert(manager.get_target_allocation(1) == 3000, 'Ekubo should be 3000');
    assert(manager.get_target_allocation(2) == 3000, 'Nostra should be 3000');

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
#[should_panic(expected: ('Already initialized', ))]
fn test_manager_double_initialize() {
    let (curator, manager_addr, manager) = setUp();

    let vault = contract_address_const::<10>();
    let token = contract_address_const::<20>();
    let vesu = contract_address_const::<100>();
    let ekubo = contract_address_const::<200>();
    let nostra = contract_address_const::<300>();

    start_prank(manager_addr, curator);
    manager.initialize(vault, curator, token, vesu, ekubo, nostra);
    stop_prank(manager_addr);
}

// ============================================================================
// Tests: Allocation Management
// ============================================================================

#[test]
fn test_set_allocations() {
    let (curator, manager_addr, manager) = setUp();

    start_prank(manager_addr, curator);
    manager.set_target_allocations(5000, 2500, 2500);
    stop_prank(manager_addr);

    assert(manager.get_target_allocation(0) == 5000, 'Vesu should be 5000');
    assert(manager.get_target_allocation(1) == 2500, 'Ekubo should be 2500');
    assert(manager.get_target_allocation(2) == 2500, 'Nostra should be 2500');
}

#[test]
#[should_panic(expected: ('Total exceeds 100%', ))]
fn test_allocations_exceed_100() {
    let (curator, manager_addr, manager) = setUp();

    start_prank(manager_addr, curator);
    manager.set_target_allocations(5000, 3000, 3000);
    stop_prank(manager_addr);
}

#[test]
fn test_partial_allocation() {
    let (curator, manager_addr, manager) = setUp();

    start_prank(manager_addr, curator);
    manager.set_target_allocations(3000, 2000, 1000);
    stop_prank(manager_addr);

    assert(manager.get_target_allocation(0) == 3000, 'Vesu should be 3000');
    assert(manager.get_target_allocation(1) == 2000, 'Ekubo should be 2000');
    assert(manager.get_target_allocation(2) == 1000, 'Nostra should be 1000');
}

// ============================================================================
// Tests: Pause/Unpause
// ============================================================================

#[test]
fn test_pause_strategy() {
    let (curator, manager_addr, manager) = setUp();

    assert(!manager.is_strategy_paused(0), 'Should not be paused');

    start_prank(manager_addr, curator);
    manager.pause_strategy(0);
    stop_prank(manager_addr);
    assert(manager.is_strategy_paused(0), 'Should be paused');

    start_prank(manager_addr, curator);
    manager.unpause_strategy(0);
    stop_prank(manager_addr);
    assert(!manager.is_strategy_paused(0), 'Should be unpaused');
}

#[test]
#[should_panic(expected: ('Only curator', ))]
fn test_non_curator_pause() {
    let (_curator, manager_addr, manager) = setUp();

    let attacker = contract_address_const::<999>();
    start_prank(manager_addr, attacker);
    manager.pause_strategy(0);
    stop_prank(manager_addr);
}

#[test]
#[should_panic(expected: ('Only curator', ))]
fn test_non_curator_set_allocations() {
    let (_curator, manager_addr, manager) = setUp();

    let attacker = contract_address_const::<999>();
    start_prank(manager_addr, attacker);
    manager.set_target_allocations(5000, 2500, 2500);
    stop_prank(manager_addr);
}

// ============================================================================
// Tests: Invalid Strategy ID
// ============================================================================

#[test]
fn test_invalid_strategy_id_returns_zero() {
    let (_curator, _manager_addr, manager) = setUp();

    assert(manager.get_target_allocation(99) == 0, 'Should return 0');
    assert(
        manager.get_adapter_address(99) == contract_address_const::<0>(), 'Should return zero addr'
    );
    assert(manager.is_strategy_paused(99), 'Invalid should be paused');
}
