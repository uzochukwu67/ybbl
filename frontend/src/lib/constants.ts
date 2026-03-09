// ── Launchpad ─────────────────────────────────────────────────────────────────
// Sepolia testnet deployment (2026-03-09)
// Class hash:    0x129a7ca85aa4ca034e7d0f906ff3b99072d9e0c4ef91b92e19d9164c1b16933
// ERC20 class:   0x2d2f4cf49064e879da0b0fb0a3c00d2e1dc3c6e59dfbdc0836da7be6cbfba
export const LAUNCHPAD_ADDRESS =
  process.env.NEXT_PUBLIC_LAUNCHPAD_ADDRESS ||
  "0x0130eced40d347abf0ed51bd37f71303c296bc8471bbeba9deb21e03666f2497";

// ── Ekubo ─────────────────────────────────────────────────────────────────────
// Addresses are identical on Sepolia and Mainnet (Ekubo upgrades in-place)
export const EKUBO_POSITIONS_MAINNET =
  "0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067";
export const EKUBO_POSITIONS_SEPOLIA =
  "0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5";
export const EKUBO_CORE_SEPOLIA =
  "0x0444a09d96389aa7148f1aada508e30b71299ffe650d9c97fdaae38cb9a23384";

// Default to Sepolia (matches the deployed launchpad)
export const EKUBO_POSITIONS = EKUBO_POSITIONS_SEPOLIA;

// ── Explorers ─────────────────────────────────────────────────────────────────
export const STARKNET_EXPLORER =
  process.env.NEXT_PUBLIC_NETWORK === "mainnet"
    ? "https://starkscan.co"
    : "https://sepolia.voyager.online";

// ── Token display ─────────────────────────────────────────────────────────────
export const TOKEN_DECIMALS = 18;
export const BASE_DECIMALS = 18;
