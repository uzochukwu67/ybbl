import { shortString } from "starknet";
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



// starknet.js v6: callContract returns string[] directly
async function callRead(library: any, fn: string, calldata: string[] = []): Promise<string[]> {
  const result = await library.callContract({
    contractAddress: LAUNCHPAD_ADDRESS,
    entrypoint: fn,
    calldata,
    blockId: "latest",
  });
  return Array.isArray(result) ? result : (result as any).result;
}

// Call any contract (not just the launchpad)
async function callAny(library: any, contractAddress: string, fn: string, calldata: string[] = []): Promise<string[]> {
  const result = await library.callContract({ contractAddress, entrypoint: fn, calldata, blockId: "latest" });
  return Array.isArray(result) ? result : (result as any).result;
}

function decodeFelt(felt: string): string {
  try { return shortString.decodeShortString(felt); } catch { return felt; }
}

// starknet.js v6: account.execute([{ contractAddress, entrypoint, calldata }])
async function callWrite(walletAccount: any, fn: string, calldata: string[]): Promise<string> {
  const res = await walletAccount.execute([{
    contractAddress: LAUNCHPAD_ADDRESS,
    entrypoint: fn,
    calldata,
  }]);
  return res.transaction_hash as string;
}

export function useLaunchpad() {
  const { library, connected, account, walletAccount } = useStarknet();
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

  const getTokenCount = useCallback(async (): Promise<number> => {
    const r = await callRead(library, "get_token_count");
    return feltToU64(r[0]);
  }, [library]);

  const getTokenByIndex = useCallback(async (index: number): Promise<string> => {
    const r = await callRead(library, "get_token_by_index", [index.toString()]);
    return r[0];
  }, [library]);

  const getTokenName = useCallback(async (tokenAddr: string): Promise<string> => {
    const r = await callAny(library, tokenAddr, "get_name");
    return decodeFelt(r[0]);
  }, [library]);

  const getTokenSymbol = useCallback(async (tokenAddr: string): Promise<string> => {
    const r = await callAny(library, tokenAddr, "get_symbol");
    return decodeFelt(r[0]);
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
    if (!walletAccount) throw new Error("Wallet not connected");
    setLoading(true);
    try {
      const hash = await callWrite(walletAccount, "launch_token", [
        encodeShortStr(name), encodeShortStr(symbol), baseAsset, vesuPoolId,
      ]);
      setTxHash(hash);
      return hash;
    } finally { setLoading(false); }
  }, [walletAccount]);

  const buy = useCallback(async (token: string, delta: bigint, maxCost: bigint, baseAsset: string): Promise<string> => {
    if (!walletAccount) throw new Error("Wallet not connected");
    setLoading(true);
    try {
      // Multicall: approve base asset spend, then buy
      const res = await walletAccount.execute([
        {
          contractAddress: baseAsset,
          entrypoint: "approve",
          calldata: [LAUNCHPAD_ADDRESS, ...u256ToCalldata(maxCost)],
        },
        {
          contractAddress: LAUNCHPAD_ADDRESS,
          entrypoint: "buy",
          calldata: [token, ...u256ToCalldata(delta), ...u256ToCalldata(maxCost)],
        },
      ]);
      const hash = res.transaction_hash as string;
      setTxHash(hash);
      return hash;
    } finally { setLoading(false); }
  }, [walletAccount]);

  const buyAnonymous = useCallback(async (token: string, delta: bigint, maxCost: bigint, nullifier: string, baseAsset: string): Promise<string> => {
    if (!walletAccount) throw new Error("Wallet not connected");
    setLoading(true);
    try {
      const res = await walletAccount.execute([
        {
          contractAddress: baseAsset,
          entrypoint: "approve",
          calldata: [LAUNCHPAD_ADDRESS, ...u256ToCalldata(maxCost)],
        },
        {
          contractAddress: LAUNCHPAD_ADDRESS,
          entrypoint: "buy_anonymous",
          calldata: [token, ...u256ToCalldata(delta), ...u256ToCalldata(maxCost), nullifier],
        },
      ]);
      const hash = res.transaction_hash as string;
      setTxHash(hash);
      return hash;
    } finally { setLoading(false); }
  }, [walletAccount]);

  const sell = useCallback(async (token: string, delta: bigint, minPayout: bigint): Promise<string> => {
    if (!walletAccount) throw new Error("Wallet not connected");
    setLoading(true);
    try {
      const hash = await callWrite(walletAccount, "sell", [token, ...u256ToCalldata(delta), ...u256ToCalldata(minPayout)]);
      setTxHash(hash);
      return hash;
    } finally { setLoading(false); }
  }, [walletAccount]);

  const graduate = useCallback(async (token: string): Promise<string> => {
    if (!walletAccount) throw new Error("Wallet not connected");
    setLoading(true);
    try {
      const hash = await callWrite(walletAccount, "graduate", [token]);
      setTxHash(hash); return hash;
    } finally { setLoading(false); }
  }, [walletAccount]);

  const collectLpFees = useCallback(async (token: string): Promise<string> => {
    if (!walletAccount) throw new Error("Wallet not connected");
    setLoading(true);
    try {
      const hash = await callWrite(walletAccount, "collect_lp_fees", [token]);
      setTxHash(hash); return hash;
    } finally { setLoading(false); }
  }, [walletAccount]);

  const harvestYield = useCallback(async (token: string): Promise<string> => {
    if (!walletAccount) throw new Error("Wallet not connected");
    setLoading(true);
    try {
      const hash = await callWrite(walletAccount, "harvest_yield", [token]);
      setTxHash(hash); return hash;
    } finally { setLoading(false); }
  }, [walletAccount]);

  return {
    connected, account, loading, txHash,
    getSupplySold, getReserve, getFees, getBaseAsset,
    isGraduated, getEkuboNftId, getYieldNftId,
    getGradThreshold, getMaxSupply, getCurveK, getTokenCount, getTokenByIndex, getTokenName, getTokenSymbol,
    getVesuPrincipal, getPendingYield,
    quoteBuy, quoteSell, isNullifierUsed,
    launchToken, buy, buyAnonymous, sell,
    graduate, collectLpFees, harvestYield,
  };
}
