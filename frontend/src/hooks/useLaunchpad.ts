import { stark } from "starknet";
import { useCallback, useState } from "react";
import { useStarknet } from "context";
import { LAUNCHPAD_ADDRESS } from "lib/constants";
import {
  u256ToCalldata,
  calldataToU256,
  feltToBool,
  feltToU64,
  encodeShortStr,
} from "lib/starknetUtils";

const sel = stark.getSelectorFromName;

async function callRead(library: any, fn: string, calldata: string[] = []): Promise<string[]> {
  const res = await library.callContract({
    contract_address: LAUNCHPAD_ADDRESS,
    entry_point_selector: sel(fn),
    calldata,
  });
  return res.result as string[];
}

async function callWrite(library: any, fn: string, calldata: string[]): Promise<string> {
  const res = await library.addTransaction({
    type: "INVOKE_FUNCTION",
    contract_address: LAUNCHPAD_ADDRESS,
    entry_point_selector: sel(fn),
    calldata,
  });
  return res.transaction_hash as string;
}

export function useLaunchpad() {
  const { library, connected, account } = useStarknet();
  const [loading, setLoading] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);

  const getSupplySold = useCallback(async (token: string): Promise<bigint> => {
    const r = await callRead(library, "get_supply_sold", [token]);
    return calldataToU256(r[0], r[1]);
  }, [library]);

  const getReserve = useCallback(async (token: string): Promise<bigint> => {
    const r = await callRead(library, "get_reserve", [token]);
    return calldataToU256(r[0], r[1]);
  }, [library]);

  const getFees = useCallback(async (token: string): Promise<bigint> => {
    const r = await callRead(library, "get_fees", [token]);
    return calldataToU256(r[0], r[1]);
  }, [library]);

  const getBaseAsset = useCallback(async (token: string): Promise<string> => {
    const r = await callRead(library, "get_base_asset", [token]);
    return r[0];
  }, [library]);

  const isGraduated = useCallback(async (token: string): Promise<boolean> => {
    const r = await callRead(library, "is_graduated", [token]);
    return feltToBool(r[0]);
  }, [library]);

  const getEkuboNftId = useCallback(async (token: string): Promise<number> => {
    const r = await callRead(library, "get_ekubo_nft_id", [token]);
    return feltToU64(r[0]);
  }, [library]);

  const getYieldNftId = useCallback(async (token: string): Promise<number> => {
    const r = await callRead(library, "get_yield_nft_id", [token]);
    return feltToU64(r[0]);
  }, [library]);

  const getGradThreshold = useCallback(async (): Promise<bigint> => {
    const r = await callRead(library, "get_grad_threshold");
    return calldataToU256(r[0], r[1]);
  }, [library]);

  const getMaxSupply = useCallback(async (): Promise<bigint> => {
    const r = await callRead(library, "get_max_supply");
    return calldataToU256(r[0], r[1]);
  }, [library]);

  const getCurveK = useCallback(async (): Promise<bigint> => {
    const r = await callRead(library, "get_curve_k");
    return calldataToU256(r[0], r[1]);
  }, [library]);

  const getVesuPrincipal = useCallback(async (token: string): Promise<bigint> => {
    const r = await callRead(library, "get_vesu_principal", [token]);
    return calldataToU256(r[0], r[1]);
  }, [library]);

  const getPendingYield = useCallback(async (token: string): Promise<bigint> => {
    try {
      const r = await callRead(library, "get_pending_yield", [token]);
      return calldataToU256(r[0], r[1]);
    } catch {
      return 0n;
    }
  }, [library]);

  const quoteBuy = useCallback(async (token: string, delta: bigint): Promise<bigint> => {
    const r = await callRead(library, "quote_buy", [token, ...u256ToCalldata(delta)]);
    return calldataToU256(r[0], r[1]);
  }, [library]);

  const quoteSell = useCallback(async (token: string, delta: bigint): Promise<bigint> => {
    const r = await callRead(library, "quote_sell", [token, ...u256ToCalldata(delta)]);
    return calldataToU256(r[0], r[1]);
  }, [library]);

  const isNullifierUsed = useCallback(async (nullifier: string): Promise<boolean> => {
    const r = await callRead(library, "is_nullifier_used", [nullifier]);
    return feltToBool(r[0]);
  }, [library]);

  const launchToken = useCallback(async (name: string, symbol: string, baseAsset: string, vesuPoolId: string = "0"): Promise<string> => {
    setLoading(true);
    try {
      const hash = await callWrite(library, "launch_token", [
        encodeShortStr(name), encodeShortStr(symbol), baseAsset, vesuPoolId,
      ]);
      setTxHash(hash);
      return hash;
    } finally { setLoading(false); }
  }, [library]);

  const buy = useCallback(async (token: string, delta: bigint, maxCost: bigint): Promise<string> => {
    setLoading(true);
    try {
      const hash = await callWrite(library, "buy", [token, ...u256ToCalldata(delta), ...u256ToCalldata(maxCost)]);
      setTxHash(hash);
      return hash;
    } finally { setLoading(false); }
  }, [library]);

  const buyAnonymous = useCallback(async (token: string, delta: bigint, maxCost: bigint, nullifier: string): Promise<string> => {
    setLoading(true);
    try {
      const hash = await callWrite(library, "buy_anonymous", [
        token, ...u256ToCalldata(delta), ...u256ToCalldata(maxCost), nullifier,
      ]);
      setTxHash(hash);
      return hash;
    } finally { setLoading(false); }
  }, [library]);

  const sell = useCallback(async (token: string, delta: bigint, minPayout: bigint): Promise<string> => {
    setLoading(true);
    try {
      const hash = await callWrite(library, "sell", [token, ...u256ToCalldata(delta), ...u256ToCalldata(minPayout)]);
      setTxHash(hash);
      return hash;
    } finally { setLoading(false); }
  }, [library]);

  const graduate = useCallback(async (token: string): Promise<string> => {
    setLoading(true);
    try {
      const hash = await callWrite(library, "graduate", [token]);
      setTxHash(hash); return hash;
    } finally { setLoading(false); }
  }, [library]);

  const collectLpFees = useCallback(async (token: string): Promise<string> => {
    setLoading(true);
    try {
      const hash = await callWrite(library, "collect_lp_fees", [token]);
      setTxHash(hash); return hash;
    } finally { setLoading(false); }
  }, [library]);

  /** Harvest accrued Vesu BTC yield → mint meme tokens → seed new Ekubo LP.
   *  BTC-yield flywheel: every harvest deepens the meme token's Ekubo liquidity. */
  const harvestYield = useCallback(async (token: string): Promise<string> => {
    setLoading(true);
    try {
      const hash = await callWrite(library, "harvest_yield", [token]);
      setTxHash(hash); return hash;
    } finally { setLoading(false); }
  }, [library]);

  return {
    connected, account, loading, txHash,
    getSupplySold, getReserve, getFees, getBaseAsset,
    isGraduated, getEkuboNftId, getYieldNftId,
    getGradThreshold, getMaxSupply, getCurveK,
    getVesuPrincipal, getPendingYield,
    quoteBuy, quoteSell, isNullifierUsed,
    launchToken, buy, buyAnonymous, sell,
    graduate, collectLpFees, harvestYield,
  };
}
