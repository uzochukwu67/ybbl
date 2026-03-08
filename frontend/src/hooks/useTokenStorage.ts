import { useCallback, useEffect, useState } from "react";

export interface StoredToken {
  address: string;
  name: string;
  symbol: string;
  baseAsset: string;
  launchedAt: number; // timestamp ms
}

const KEY = "ybbc_tokens";

function load(): StoredToken[] {
  if (typeof window === "undefined") return [];
  try {
    return JSON.parse(localStorage.getItem(KEY) || "[]");
  } catch {
    return [];
  }
}

function save(tokens: StoredToken[]) {
  if (typeof window === "undefined") return;
  localStorage.setItem(KEY, JSON.stringify(tokens));
}

export function useTokenStorage() {
  const [tokens, setTokens] = useState<StoredToken[]>([]);

  useEffect(() => {
    setTokens(load());
  }, []);

  const addToken = useCallback((t: StoredToken) => {
    setTokens((prev) => {
      const exists = prev.some((p) => p.address === t.address);
      if (exists) return prev;
      const next = [t, ...prev];
      save(next);
      return next;
    });
  }, []);

  const removeToken = useCallback((address: string) => {
    setTokens((prev) => {
      const next = prev.filter((t) => t.address !== address);
      save(next);
      return next;
    });
  }, []);

  return { tokens, addToken, removeToken };
}
