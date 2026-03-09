import {
  Alert,
  AlertIcon,
  Box,
  Button,
  FormControl,
  FormHelperText,
  FormLabel,
  Heading,
  HStack,
  Input,
  Link,
  Select,
  Text,
  VStack,
} from "@chakra-ui/react";
import { useCallback, useState } from "react";
import { useLaunchpad } from "hooks/useLaunchpad";
import { useTokenStorage } from "hooks/useTokenStorage";
import { STARKNET_EXPLORER } from "lib/constants";
import { shortAddr } from "lib/starknetUtils";

interface AssetOption {
  label: string;
  address: string;
  decimals: number;
  symbol: string;
  /** Vesu pool ID for this asset (mainnet Genesis pool). "0" = Vesu disabled. */
  vesuPoolId: string;
}

// Mainnet token addresses + their Vesu Genesis pool IDs
const KNOWN_ASSETS: AssetOption[] = [
  {
    label: "wBTC (recommended)",
    address:
      "0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac",
    decimals: 8,
    symbol: "wBTC",
    vesuPoolId:
      "0x4dc4ea5ec84beddca0f33c4e1b0a6b62d281e0e9b34eaec6a7aa9e54e20e",
  },
  {
    label: "USDC",
    address:
      "0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8",
    decimals: 6,
    symbol: "USDC",
    vesuPoolId:
      "0x4dc4ea5ec84beddca0f33c4e1b0a6b62d281e0e9b34eaec6a7aa9e54e20e",
  },
  {
    label: "STRK",
    address:
      "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
    decimals: 18,
    symbol: "STRK",
    vesuPoolId:
      "0x4dc4ea5ec84beddca0f33c4e1b0a6b62d281e0e9b34eaec6a7aa9e54e20e",
  },
  {
    label: "Custom",
    address: "",
    decimals: 18,
    symbol: "",
    vesuPoolId: "0",
  },
];

const Launch = () => {
  const { launchToken, connected, loading } = useLaunchpad();
  const { addToken } = useTokenStorage();

  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [selectedAsset, setSelectedAsset] = useState("wBTC (recommended)");
  const [customAddress, setCustomAddress] = useState("");
  const [error, setError] = useState("");
  const [txHash, setTxHash] = useState("");

  const assetInfo =
    KNOWN_ASSETS.find((a) => a.label === selectedAsset) ?? KNOWN_ASSETS[0];
  const baseAsset =
    assetInfo.label === "Custom" ? customAddress : assetInfo.address;
  const isCustom = assetInfo.label === "Custom";

  const handleLaunch = useCallback(async () => {
    setError("");
    if (!name.trim()) {
      setError("Token name required");
      return;
    }
    if (!symbol.trim() || symbol.length > 8) {
      setError("Symbol required (max 8 chars)");
      return;
    }
    if (!baseAsset.startsWith("0x")) {
      setError("Invalid base asset address");
      return;
    }

    try {
      const vesuPoolId = isCustom ? "0" : assetInfo.vesuPoolId ?? "0";
      const hash = await launchToken(
        name.trim(),
        symbol.trim().toUpperCase(),
        baseAsset,
        vesuPoolId
      );
      setTxHash(hash);
      addToken({
        address: hash,
        name: name.trim(),
        symbol: symbol.trim().toUpperCase(),
        baseAsset,
        launchedAt: Date.now(),
      });
    } catch (e: any) {
      setError(e?.message || "Transaction failed");
    }
  }, [
    name,
    symbol,
    baseAsset,
    assetInfo.vesuPoolId,
    isCustom,
    launchToken,
    addToken,
  ]);

  return (
    <Box maxW="560px">
      <Box mb={8}>
        <Heading fontSize="2xl" color="dark.50" mb={2}>
          Launch a Token
        </Heading>
        <Text color="dark.300" fontSize="sm">
          Deploy a new bonding curve token. No presale, no VCs, just a fair
          curve.
        </Text>
      </Box>

      {!connected && (
        <Alert
          status="warning"
          bg="dark.800"
          borderRadius="lg"
          mb={6}
          border="1px solid"
          borderColor="yellow.800"
        >
          <AlertIcon color="yellow.400" />
          <Text fontSize="sm" color="dark.200">
            Connect your wallet to launch a token.
          </Text>
        </Alert>
      )}

      <VStack spacing={5} align="stretch">
        <FormControl isRequired>
          <FormLabel fontSize="sm" color="dark.200">
            Token Name
          </FormLabel>
          <Input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Bitcoin Cat"
            maxLength={31}
            bg="dark.800"
            border="1px solid"
            borderColor="dark.600"
            _focus={{ borderColor: "brand.500", boxShadow: "none" }}
            _hover={{ borderColor: "dark.500" }}
            color="dark.50"
          />
          <FormHelperText color="dark.400" fontSize="xs">
            Max 31 characters (Cairo short string)
          </FormHelperText>
        </FormControl>

        <FormControl isRequired>
          <FormLabel fontSize="sm" color="dark.200">
            Symbol
          </FormLabel>
          <Input
            value={symbol}
            onChange={(e) => setSymbol(e.target.value.toUpperCase())}
            placeholder="BCAT"
            maxLength={8}
            bg="dark.800"
            border="1px solid"
            borderColor="dark.600"
            _focus={{ borderColor: "brand.500", boxShadow: "none" }}
            _hover={{ borderColor: "dark.500" }}
            color="dark.50"
          />
        </FormControl>

        <FormControl>
          <FormLabel fontSize="sm" color="dark.200">
            Base Asset
          </FormLabel>
          <Select
            value={selectedAsset}
            onChange={(e) => setSelectedAsset(e.target.value)}
            bg="dark.800"
            border="1px solid"
            borderColor="dark.600"
            _focus={{ borderColor: "brand.500", boxShadow: "none" }}
            _hover={{ borderColor: "dark.500" }}
            color="dark.50"
            mb={isCustom ? 2 : 0}
          >
            {KNOWN_ASSETS.map((a) => (
              <option
                key={a.label}
                value={a.label}
                style={{ background: "#1a1a2e" }}
              >
                {a.label}
              </option>
            ))}
          </Select>

          {!isCustom && (
            <FormHelperText color="dark.400" fontSize="xs" fontFamily="mono">
              {assetInfo.address}
            </FormHelperText>
          )}

          {isCustom && (
            <Input
              value={customAddress}
              onChange={(e) => setCustomAddress(e.target.value)}
              placeholder="0x..."
              bg="dark.800"
              border="1px solid"
              borderColor="dark.600"
              _focus={{ borderColor: "brand.500", boxShadow: "none" }}
              _hover={{ borderColor: "dark.500" }}
              color="dark.50"
              fontFamily="mono"
              fontSize="sm"
            />
          )}

          <FormHelperText color="dark.400" fontSize="xs" mt={1}>
            wBTC is recommended — reserve earns yield via Vesu after graduation.
          </FormHelperText>
        </FormControl>

        {/* Preview box */}
        <Box
          bg="dark.800"
          border="1px solid"
          borderColor="dark.600"
          borderRadius="lg"
          p={4}
        >
          <Text fontSize="xs" color="dark.300" mb={3} fontWeight="semibold">
            DEPLOYMENT PREVIEW
          </Text>
          <VStack align="stretch" spacing={2} fontSize="sm">
            {[
              ["Name", name || "—"],
              ["Symbol", symbol || "—"],
              ["Decimals", "18"],
              [
                "Base asset",
                isCustom
                  ? customAddress
                    ? shortAddr(customAddress)
                    : "—"
                  : assetInfo.symbol,
              ],
              ["Initial price", "K × 1"],
              ["Graduation", "Set by launchpad config"],
              ["LP destination", "Ekubo full-range"],
              ["Reserve yield", "Vesu"],
            ].map(([k, v]) => (
              <HStack key={k} justify="space-between">
                <Text color="dark.400">{k}</Text>
                <Text
                  color="dark.100"
                  fontFamily={k === "Symbol" ? "mono" : undefined}
                >
                  {v}
                </Text>
              </HStack>
            ))}
          </VStack>
        </Box>

        {error && (
          <Text fontSize="sm" color="red.400">
            {error}
          </Text>
        )}

        {txHash && (
          <Alert
            status="success"
            bg="dark.800"
            borderRadius="lg"
            border="1px solid"
            borderColor="green.800"
          >
            <AlertIcon color="green.400" />
            <Box>
              <Text fontSize="sm" color="dark.50" mb={1}>
                Token launch submitted!
              </Text>
              <Link
                href={`${STARKNET_EXPLORER}/tx/${txHash}`}
                isExternal
                fontSize="xs"
                color="brand.400"
              >
                View tx: {shortAddr(txHash)}
              </Link>
              <Text fontSize="xs" color="dark.300" mt={1}>
                After the transaction confirms, find the deployed token address
                in the tx receipt and{" "}
                <Link href="/explore" color="brand.400">
                  import it in Explore
                </Link>
                .
              </Text>
            </Box>
          </Alert>
        )}

        <Button
          bg="brand.500"
          color="dark.900"
          _hover={{ bg: "brand.400" }}
          _active={{ bg: "brand.600" }}
          isLoading={loading}
          isDisabled={!connected}
          onClick={handleLaunch}
          fontWeight="bold"
          size="lg"
        >
          {!connected ? "Connect wallet first" : "Launch Token"}
        </Button>
      </VStack>
    </Box>
  );
};

export default Launch;
