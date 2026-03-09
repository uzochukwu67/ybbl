import { connect } from "@argent/get-starknet";
import { toast } from "material-react-toastify";
import React from "react";
import { RpcProvider } from "starknet";

import { StarknetState } from "./model";

// Public Sepolia JSON-RPC endpoint (feeder gateway is deprecated on Sepolia)
const sepoliaProvider = new RpcProvider({
  nodeUrl: "https://starknet-sepolia.public.blastapi.io/rpc/v0_7",
});

interface StarknetManagerState {
  account?: string;
  connected?: boolean;
  library: RpcProvider;
  walletAccount?: any;
}

interface SetAccount {
  type: "set_account";
  account: string;
}

interface SetConnected {
  type: "set_connected";
  con: boolean;
}

interface SetWalletAccount {
  type: "set_wallet_account";
  walletAccount: any;
}

type Action = SetAccount | SetConnected | SetWalletAccount;

function reducer(
  state: StarknetManagerState,
  action: Action
): StarknetManagerState {
  switch (action.type) {
    case "set_account": {
      return { ...state, account: action.account };
    }
    case "set_connected": {
      return { ...state, connected: action.con };
    }
    case "set_wallet_account": {
      return { ...state, walletAccount: action.walletAccount };
    }
    default: {
      return state;
    }
  }
}

const toastOpts = {
  position: "top-left" as const,
  autoClose: 4000,
  hideProgressBar: true,
  closeOnClick: true,
  pauseOnHover: true,
  draggable: true,
};

const useStarknetManager = (): StarknetState => {
  const [state, dispatch] = React.useReducer(reducer, {
    library: sepoliaProvider,
  });

  const { account, connected, library, walletAccount } = state;

  const checkMissingWallet = React.useCallback(async () => {
    try {
      const wallet = await connect({ modalMode: "neverAsk" });
      if (!wallet) throw new Error("No wallet");
      await wallet.enable();
    } catch {
      toast.error("⚠️ Argent-X wallet extension missing!", toastOpts);
    }
  }, []);

  const connectBrowserWallet = React.useCallback(async () => {
    try {
      const wallet = await connect({ modalMode: "alwaysAsk" });
      if (!wallet) throw new Error("No wallet found");
      await wallet.enable();
      const address = wallet.selectedAddress;
      if (!address) throw new Error("No address returned");
      dispatch({ type: "set_account", account: address });
      dispatch({ type: "set_wallet_account", walletAccount: wallet.account });
      dispatch({ type: "set_connected", con: true });
    } catch {
      toast.error("⚠️ Argent-X wallet extension missing!", {
        ...toastOpts,
        autoClose: 2000,
      });
    }
  }, []);

  const setConnected = React.useCallback(async (con: boolean) => {
    dispatch({ type: "set_connected", con });
    if (!con) {
      dispatch({ type: "set_account", account: "" });
      dispatch({ type: "set_wallet_account", walletAccount: undefined });
    }
  }, []);

  return {
    account,
    connected,
    setConnected,
    connectBrowserWallet,
    checkMissingWallet,
    library,
    walletAccount,
  };
};

export default useStarknetManager;
