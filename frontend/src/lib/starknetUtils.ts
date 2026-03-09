import { shortString } from "starknet";

// ── u256 calldata helpers ────────────────────────────────────────────────────

/** Encode a bigint as a Cairo u256 (two felt252 calldata elements: [low, high]) */
export const u256ToCalldata = (n: bigint): string[] => [
  (n & ((1n << 128n) - 1n)).toString(),
  (n >> 128n).toString(),
];

/** Decode two hex felt strings from Cairo u256 result into a bigint */
export const calldataToU256 = (low: string, high: string): bigint =>
  BigInt(low) + BigInt(high) * (1n << 128n);

/** Decode a single hex felt as bigint */
export const feltToBigInt = (felt: string): bigint => BigInt(felt);

/** Decode a boolean felt ('0x0' | '0x1') */
export const feltToBool = (felt: string): boolean =>
  felt !== "0x0" && felt !== "0";

/** Decode a u64 felt */
export const feltToU64 = (felt: string): number => Number(BigInt(felt));

// ── Short string (felt252 names) ─────────────────────────────────────────────

export const encodeShortStr = (s: string): string => {
  try {
    return shortString.encodeShortString(s);
  } catch {
    // truncate to 31 chars if too long
    return shortString.encodeShortString(s.slice(0, 31));
  }
};

// ── Display formatting ───────────────────────────────────────────────────────

const SCALE = BigInt(10 ** 18);

/** Format a raw u256 bigint (18 decimals) as a human-readable string */
export const formatUnits = (raw: bigint, decimals = 18): string => {
  if (raw === 0n) return "0";
  const scale = 10n ** BigInt(decimals);
  const whole = raw / scale;
  const frac = raw % scale;
  if (frac === 0n) return whole.toLocaleString();
  const fracStr = frac.toString().padStart(decimals, "0").replace(/0+$/, "");
  return `${whole.toLocaleString()}.${fracStr.slice(0, 4)}`;
};

/** Parse a human number string to raw bigint (18 decimals) */
export const parseUnits = (s: string, decimals = 18): bigint => {
  if (!s || s === ".") return 0n;
  const [whole, frac = ""] = s.split(".");
  const fracPadded = (frac + "0".repeat(decimals)).slice(0, decimals);
  return (
    BigInt(whole || "0") * 10n ** BigInt(decimals) + BigInt(fracPadded || "0")
  );
};

/** Format a raw bonding curve price (K*(2S+Δ)*Δ / Δ = K*(2S+1)) with 4 sig figs */
export const formatPrice = (raw: bigint): string => {
  if (raw === 0n) return "0";
  if (raw < 10000n) return raw.toString();
  return formatUnits(raw);
};

/** Shorten an address for display: 0x1234...abcd */
export const shortAddr = (addr: string): string => {
  if (!addr || addr.length < 10) return addr;
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
};

// ── Bonding curve math (mirrors Cairo contract) ──────────────────────────────

/** Buy cost (raw): K*(2S+delta)*delta */
export const buyCost = (k: bigint, supply: bigint, delta: bigint): bigint =>
  k * (2n * supply + delta) * delta;

/** Sell payout (raw): K*(2S-delta)*delta */
export const sellPayout = (k: bigint, supply: bigint, delta: bigint): bigint =>
  supply >= delta ? k * (2n * supply - delta) * delta : 0n;

/** Spot price (marginal): K*(2S+1) */
export const spotPrice = (k: bigint, supply: bigint): bigint =>
  k * (2n * supply + 1n);

/** Add 1% fee on top of cost */
export const withFee = (cost: bigint): bigint => cost + cost / 100n;

/** Remove 1% fee from payout */
export const withoutFee = (payout: bigint): bigint => payout - payout / 100n;

/** Graduation progress 0-100 */
export const gradProgress = (reserve: bigint, threshold: bigint): number => {
  if (threshold === 0n) return 0;
  const pct = Number((reserve * 100n) / threshold);
  return Math.min(pct, 100);
};

// ── Curve chart data ──────────────────────────────────────────────────────────

/** Generate N points for the bonding curve price line [{ supply, price }] */
export const curvePoints = (
  k: bigint,
  maxSupply: bigint,
  currentSupply: bigint,
  n = 80
): { supply: number; price: number; sold: boolean }[] => {
  const points = [];
  const step = maxSupply / BigInt(n);
  for (let i = 0; i <= n; i++) {
    const s = step * BigInt(i);
    const price = Number(spotPrice(k, s));
    points.push({
      supply: Number(s),
      price,
      sold: s <= currentSupply,
    });
  }
  return points;
};

export { SCALE };
