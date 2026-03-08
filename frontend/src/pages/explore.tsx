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
import { useEffect, useState } from "react";
import { useTokenStorage } from "hooks/useTokenStorage";
import { useLaunchpad } from "hooks/useLaunchpad";
import { TokenCard } from "components/launchpad/TokenCard";

interface TokenState {
  reserve: bigint;
  threshold: bigint;
  graduated: boolean;
}

const Explore = () => {
  const { tokens, addToken } = useTokenStorage();
  const { getReserve, getGradThreshold, isGraduated } = useLaunchpad();
  const [states, setStates] = useState<Record<string, TokenState>>({});
  const [importAddr, setImportAddr] = useState("");
  const [importing, setImporting] = useState(false);
  const [importError, setImportError] = useState("");

  // Fetch on-chain state for each stored token
  useEffect(() => {
    if (!tokens.length) return;
    const load = async () => {
      const result: Record<string, TokenState> = {};
      for (const t of tokens) {
        try {
          const [reserve, threshold, graduated] = await Promise.all([
            getReserve(t.address),
            getGradThreshold(),
            isGraduated(t.address),
          ]);
          result[t.address] = { reserve, threshold, graduated };
        } catch {
          result[t.address] = { reserve: 0n, threshold: 0n, graduated: false };
        }
      }
      setStates(result);
    };
    load();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tokens.length]);

  const handleImport = async () => {
    setImportError("");
    const addr = importAddr.trim();
    if (!addr.startsWith("0x") || addr.length < 10) {
      setImportError("Enter a valid Starknet address");
      return;
    }
    setImporting(true);
    try {
      const graduated = await isGraduated(addr);
      addToken({
        address: addr,
        name: "Unknown",
        symbol: "???",
        baseAsset: "0x0",
        launchedAt: Date.now(),
      });
      setImportAddr("");
    } catch {
      setImportError("Could not read token — check the address");
    } finally {
      setImporting(false);
    }
  };

  return (
    <Box>
      <Box mb={8}>
        <Heading fontSize="2xl" color="dark.50" mb={2}>
          Explore Tokens
        </Heading>
        <Text color="dark.300" fontSize="sm">
          Tokens launched on the YBBC bonding curve launchpad.
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
        <Box d="flex" gap={3} flexWrap="wrap">
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
          <Text color="red.400" fontSize="sm" mt={2}>{importError}</Text>
        )}
      </Box>

      {/* Token grid */}
      {tokens.length === 0 ? (
        <VStack py={16} spacing={4}>
          <Text fontSize="4xl">🪙</Text>
          <Text color="dark.300" fontSize="md">No tokens yet.</Text>
          <Link href="/launch" passHref>
            <Button
              as="a"
              bg="brand.500"
              color="dark.900"
              _hover={{ bg: "brand.400" }}
              fontWeight="bold"
            >
              Launch the first one
            </Button>
          </Link>
        </VStack>
      ) : (
        <SimpleGrid columns={[1, 2, 3]} spacing={5}>
          {tokens.map((t) => (
            <TokenCard
              key={t.address}
              token={t}
              reserve={states[t.address]?.reserve ?? 0n}
              threshold={states[t.address]?.threshold ?? 0n}
              graduated={states[t.address]?.graduated ?? false}
            />
          ))}
        </SimpleGrid>
      )}
    </Box>
  );
};

export default Explore;
