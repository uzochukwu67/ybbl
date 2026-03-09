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
    nodeUrl: "https://starknet-sepolia.public.blastapi.io/rpc/v0_7",
  }),
  walletAccount: undefined,
};
