// Anonymous Buy ZK Nullifier Proof
// 
// This circuit proves knowledge of a secret key that generates a nullifier
// without revealing the secret. This enables anonymous purchases on the
// Yield-Bearing Bonding Curve Launchpad.
// 
// Public inputs:
//   - nullifier: The hash that will be recorded on-chain to prevent replay
//   - token: The token being purchased
//   - delta: Amount of tokens being bought
//   - max_cost: Maximum acceptable cost (for slippage protection)
//   - nonce: Random nonce to ensure unique nullifier per purchase
//
// Private inputs:
//   - secret: The user's secret key (never revealed)

use std::hash::pedersen_hash;

fn main(
    // Public inputs
    nullifier: Field,
    token: Field,
    delta: Field,
    max_cost: Field,
    nonce: Field,
    // Private inputs
    secret: Field,
) -> pub Field {
    // The nullifier is computed as: hash(secret, nonce)
    // This ensures:
    // 1. Each purchase has a unique nullifier
    // 2. The secret cannot be derived from the nullifier
    // 3. The buyer can prove they generated the nullifier
    
    let computed_nullifier = pedersen_hash([secret, nonce]);
    
    // Constraint: computed nullifier must match the provided nullifier
    // This proves the prover knows the secret without revealing it
    assert(computed_nullifier == nullifier, "Invalid nullifier");
    
    // Additional constraints:
    // 1. delta > 0 (can't buy 0 tokens)
    assert(delta != 0, "Zero delta");
    
    // 2. max_cost > 0 (must specify max cost)
    assert(max_cost != 0, "Zero max_cost");
    
    // 3. nonce > 0 (must have unique nonce)
    assert(nonce != 0, "Zero nonce");
    
    // Return a commitment that can be used as a secondary check
    // This is useful if we want to verify the proof was generated for this specific purchase
    let commitment = pedersen_hash([nullifier, token, delta, max_cost]);
    commitment
}

#[test]
fn test_valid_nullifier() {
    let secret = 123456789;
    let nonce = 987654321;
    let nullifier = pedersen_hash([secret, nonce]);
    let token = 1;
    let delta = 100;
    let max_cost = 1000;
    
    main(nullifier, token, delta, max_cost, nonce, secret);
}

#[test]
fn test_different_nonce_different_nullifier() {
    let secret = 123456789;
    let nonce1 = 111;
    let nonce2 = 222;
    
    let nullifier1 = pedersen_hash([secret, nonce1]);
    let nullifier2 = pedersen_hash([secret, nonce2]);
    
    // Different nonces produce different nullifiers
    assert(nullifier1 != nullifier2, "Same nullifier");
    
    // Both should work independently
    let token = 1;
    let delta = 100;
    let max_cost = 1000;
    
    main(nullifier1, token, delta, max_cost, nonce1, secret);
    main(nullifier2, token, delta, max_cost, nonce2, secret);
}

#[test(should_fail)]
fn test_wrong_secret() {
    let secret = 123456789;
    let wrong_secret = 987654321;
    let nonce = 111;
    let nullifier = pedersen_hash([secret, nonce]); // Nullifier computed with correct secret
    
    let token = 1;
    let delta = 100;
    let max_cost = 1000;
    
    // This should fail because we're proving with wrong secret
    main(nullifier, token, delta, max_cost, nonce, wrong_secret);
}
