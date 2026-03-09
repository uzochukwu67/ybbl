import {
  Box,
  Button,
  Heading,
  Input,
  SimpleGrid,
  Spinner,
  Text,
  VStack,
} from "@chakra-ui/react";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { useTokenStorage } from "hooks/useTokenStorage";
import { useLaunchpad } from "hooks/useLaunchpad";
import { TokenCard } from "components/launchpad/TokenCard";
import { spotPrice } from "lib/starknetUtils";

interface TokenState {
  reserve: bigint;
  threshold: bigint;
  graduated: boolean;
  supply: bigint;
  baseAsset: string;
}

const Explore = () => {
  const { tokens, addToken } = useTokenStorage();
  const {
    getReserve,
    getGradThreshold,
    isGraduated,
    getSupplySold,
    getCurveK,
    getTokenCount,
    getTokenByIndex,
    getBaseAsset,
    getTokenName,
    getTokenSymbol,
  } = useLaunchpad();
  const [states, setStates] = useState<Record<string, TokenState>>({});
  const [curveK, setCurveK] = useState<bigint>(0n);
  const [importAddr, setImportAddr] = useState("");
  const [importing, setImporting] = useState(false);
  const [importError, setImportError] = useState("");
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [loadStatus, setLoadStatus] = useState("Connecting to chain...");
  const [retryCount, setRetryCount] = useState(0);

  const retry = useCallback(() => {
    setLoadError("");
    setLoading(true);
    setLoadStatus("Connecting to chain...");
    setRetryCount((c) => c + 1);
  }, []);

  // On mount (and on retry): fetch all on-chain tokens and merge with localStorage
  useEffect(() => {
    const load = async () => {
      try {
        console.log("[Explore] Fetching curveK and token count...");
        setLoadStatus("Fetching token list from contract...");
        const [k, count] = await Promise.all([getCurveK(), getTokenCount()]);
        console.log("[Explore] curveK:", k.toString(), "| token count:", count);
        setCurveK(k);

        if (count === 0) {
          console.log("[Explore] No tokens launched yet.");
          setLoading(false);
          return;
        }

        setLoadStatus(`Found ${count} token(s) — loading details...`);

        // Fetch all token addresses from the contract
        console.log("[Explore] Fetching addresses for", count, "token(s)...");
        const addresses = await Promise.all(
          Array.from({ length: count }, (_, i) => getTokenByIndex(i))
        );
        console.log("[Explore] Token addresses:", addresses);

        // Fetch state for each token
        const [threshold, entries] = await Promise.all([
          getGradThreshold(),
          Promise.all(
            addresses.map(async (addr) => {
              try {
                console.log("[Explore] Loading state for", addr);
                const [reserve, graduated, supply, baseAsset] = await Promise.all([
                  getReserve(addr),
                  isGraduated(addr),
                  getSupplySold(addr),
                  getBaseAsset(addr),
                ]);
                console.log("[Explore]", addr, "→ reserve:", reserve.toString(), "supply:", supply.toString(), "graduated:", graduated, "baseAsset:", baseAsset);
                return [addr, { reserve, threshold: 0n, graduated, supply, baseAsset }] as const;
              } catch (e) {
                console.warn("[Explore] Failed to load state for", addr, e);
                return [addr, { reserve: 0n, threshold: 0n, graduated: false, supply: 0n, baseAsset: "0x0" }] as const;
              }
            })
          ),
        ]);

        const stateMap: Record<string, TokenState> = {};
        for (const [addr, s] of entries) {
          stateMap[addr] = { ...s, threshold };
          // Auto-add unknown on-chain tokens to local storage with real name/symbol
          if (!tokens.some((t) => t.address === addr)) {
            console.log("[Explore] Auto-adding unknown token to localStorage:", addr);
            const [name, symbol] = await Promise.all([
              getTokenName(addr).catch(() => "Unknown"),
              getTokenSymbol(addr).catch(() => "???"),
            ]);
            console.log("[Explore] Token name/symbol:", name, symbol);
            addToken({ address: addr, name, symbol, baseAsset: s.baseAsset, launchedAt: Date.now() });
          }
        }
        console.log("[Explore] Done. Final state map:", stateMap);
        setStates(stateMap);
      } catch (e) {
        console.error("[Explore] Failed to load tokens from chain:", e);
        setLoadError("Could not load tokens from chain. Check the console for details.");
      } finally {
        setLoading(false);
      }
    };
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [retryCount]);

  const handleImport = async () => {
    setImportError("");
    const addr = importAddr.trim();
    if (!addr.startsWith("0x") || addr.length < 10) {
      setImportError("Enter a valid Starknet address");
      return;
    }
    setImporting(true);
    try {
      const baseAsset = await getBaseAsset(addr);
      addToken({ address: addr, name: "Unknown", symbol: "???", baseAsset, launchedAt: Date.now() });
      setImportAddr("");
    } catch {
      setImportError("Could not read token — check the address");
    } finally {
      setImporting(false);
    }
  };

  // Merge: on-chain addresses first, then localStorage extras that have a valid baseAsset
  // (filters out stale tx-hash-as-address entries from old launches)
  const allAddresses = [
    ...Object.keys(states),
    ...tokens
      .filter((t) => !states[t.address] && t.baseAsset && t.baseAsset !== "0x0")
      .map((t) => t.address),
  ];

  return (
    <Box>
      <Box mb={8}>
        <Heading fontSize="2xl" color="dark.50" mb={2}>
          Explore Tokens
        </Heading>
        <Text color="dark.300" fontSize="sm">
          All tokens launched on the YBBC bonding curve launchpad.
        </Text>
      </Box>

      {/* Import by address */}
      <Box
        bg="dark.800"
        border="1px solid"
        borderColor="dark.600"
        borderRadius="xl"
        p={5}
        mb={8}
      >
        <Text fontWeight="semibold" color="dark.50" mb={3} fontSize="sm">
          Import token by address
        </Text>
        <Box display="flex" gap={3} flexWrap="wrap">
          <Input
            value={importAddr}
            onChange={(e) => setImportAddr(e.target.value)}
            placeholder="0x..."
            bg="dark.900"
            border="1px solid"
            borderColor="dark.600"
            _focus={{ borderColor: "brand.500", boxShadow: "none" }}
            color="dark.50"
            flex="1"
            minW="240px"
          />
          <Button
            bg="brand.500"
            color="dark.900"
            _hover={{ bg: "brand.400" }}
            isLoading={importing}
            onClick={handleImport}
            fontWeight="bold"
          >
            Import
          </Button>
        </Box>
        {importError && (
          <Text color="red.400" fontSize="sm" mt={2}>
            {importError}
          </Text>
        )}
      </Box>

      {/* Token grid */}
      {loading ? (
        <VStack py={16} spacing={4}>
          <Spinner size="lg" color="brand.500" thickness="3px" />
          <Text color="dark.400" fontSize="sm">{loadStatus}</Text>
        </VStack>
      ) : loadError ? (
        <VStack py={16} spacing={4}>
          <Text fontSize="3xl">⚠️</Text>
          <Text color="red.400" fontSize="sm" textAlign="center" maxW="400px">{loadError}</Text>
          <Button
            size="sm"
            variant="outline"
            borderColor="dark.600"
            color="dark.300"
            onClick={() => { setLoadError(""); setLoading(true); }}
          >
            Retry
          </Button>
        </VStack>
      ) : allAddresses.length === 0 ? (
        <VStack py={16} spacing={4}>
          <Text fontSize="4xl">🪙</Text>
          <Text color="dark.300" fontSize="md">No tokens yet.</Text>
          <Link href="/launch" passHref>
            <Button as="a" bg="brand.500" color="dark.900" _hover={{ bg: "brand.400" }} fontWeight="bold">
              Launch the first one
            </Button>
          </Link>
        </VStack>
      ) : (
        <SimpleGrid columns={[1, 2, 3]} spacing={5}>
          {allAddresses.map((addr) => {
            const s = states[addr];
            const stored = tokens.find((t) => t.address === addr);
            const price = curveK > 0n && s ? spotPrice(curveK, s.supply) : 0n;
            const baseAsset = s?.baseAsset ?? stored?.baseAsset ?? "0x0";
            return (
              <TokenCard
                key={addr}
                token={{
                  address: addr,
                  name: stored?.name ?? "Unknown",
                  symbol: stored?.symbol ?? "???",
                  baseAsset,
                  launchedAt: stored?.launchedAt ?? 0,
                }}
                reserve={s?.reserve ?? 0n}
                threshold={s?.threshold ?? 0n}
                graduated={s?.graduated ?? false}
                spotPrice={price}
              />
            );
          })}
        </SimpleGrid>
      )}
    </Box>
  );
};

export default Explore;
