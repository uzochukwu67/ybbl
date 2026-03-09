import { RpcProvider } from "starknet";

export interface StarknetState {
  account?: string;
  connected?: boolean;
  connectBrowserWallet: () => void;
  checkMissingWallet: () => void;
  setConnected: (con: boolean) => void;
  library: RpcProvider;
  /** The wallet Account object (from @argent/get-starknet) used for signing transactions. */
  walletAccount?: any;
}

export const STARKNET_STATE_INITIAL_STATE: StarknetState = {
  account: undefined,
  connected: false,
  connectBrowserWallet: () => undefined,
  checkMissingWallet: () => undefined,
  setConnected: () => undefined,
  library: new RpcProvider({
    nodeUrl: process.env.NEXT_PUBLIC_RPC_URL ||
      "https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_10/_5S7tSyp-pRnFg3J8gpIQ",
  }),
  walletAccount: undefined,
};
