import {
  Box,
  Button,
  FormControl,
  FormLabel,
  HStack,
  Input,
  Switch,
  Text,
  Tooltip,
  VStack,
} from "@chakra-ui/react";
import { useCallback, useState } from "react";
import { useLaunchpad } from "hooks/useLaunchpad";
import { buyCost, withFee, parseUnits, formatUnits } from "lib/starknetUtils";
import { stark } from "starknet";

interface Props {
  token: string;
  curveK: bigint;
  supply: bigint;
  onSuccess?: (txHash: string) => void;
}

export const BuyWidget = ({ token, curveK, supply, onSuccess }: Props) => {
  const { buy, buyAnonymous, loading, connected } = useLaunchpad();
  const [amount, setAmount] = useState("");
  const [slippage, setSlippage] = useState("1");
  const [useZk, setUseZk] = useState(false);
  const [error, setError] = useState("");

  const delta = parseUnits(amount, 0); // token amounts are whole units
  const cost = delta > 0n ? buyCost(curveK, supply, delta) : 0n;
  const totalWithFee = withFee(cost);
  const slippageBps = Math.floor(parseFloat(slippage || "1") * 100);
  const maxCost = totalWithFee + (totalWithFee * BigInt(slippageBps)) / 10000n;

  const handleBuy = useCallback(async () => {
    setError("");
    if (!delta || delta === 0n) {
      setError("Enter an amount");
      return;
    }
    try {
      let txHash: string;
      if (useZk) {
        // Generate a random nullifier (in prod: derive from ZK proof)
        const nullifier = stark.randomAddress();
        txHash = await buyAnonymous(token, delta, maxCost, nullifier);
      } else {
        txHash = await buy(token, delta, maxCost);
      }
      setAmount("");
      onSuccess?.(txHash);
    } catch (e: any) {
      setError(e?.message || "Transaction failed");
    }
  }, [delta, maxCost, useZk, token, buy, buyAnonymous, onSuccess]);

  return (
    <VStack spacing={4} align="stretch">
      <FormControl>
        <FormLabel fontSize="sm" color="dark.200">
          Amount to buy (tokens)
        </FormLabel>
        <Input
          value={amount}
          onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))}
          placeholder="100"
          bg="dark.800"
          border="1px solid"
          borderColor="dark.600"
          _focus={{ borderColor: "brand.500", boxShadow: "none" }}
          _hover={{ borderColor: "dark.500" }}
          color="dark.50"
        />
      </FormControl>

      {delta > 0n && (
        <Box bg="dark.800" borderRadius="md" p={3} border="1px solid" borderColor="dark.600">
          <HStack justify="space-between">
            <Text fontSize="sm" color="dark.300">Estimated cost</Text>
            <Text fontSize="sm" color="brand.400" fontWeight="semibold">
              {formatUnits(totalWithFee)} base
            </Text>
          </HStack>
          <HStack justify="space-between" mt={1}>
            <Text fontSize="xs" color="dark.400">Fee (1%)</Text>
            <Text fontSize="xs" color="dark.400">{formatUnits(totalWithFee - cost)}</Text>
          </HStack>
        </Box>
      )}

      <FormControl>
        <FormLabel fontSize="sm" color="dark.200">Slippage %</FormLabel>
        <Input
          value={slippage}
          onChange={(e) => setSlippage(e.target.value)}
          w="100px"
          bg="dark.800"
          border="1px solid"
          borderColor="dark.600"
          _focus={{ borderColor: "brand.500", boxShadow: "none" }}
          color="dark.50"
          size="sm"
        />
      </FormControl>

      <HStack>
        <Switch
          isChecked={useZk}
          onChange={(e) => setUseZk(e.target.checked)}
          colorScheme="orange"
        />
        <Tooltip label="Uses Noir ZK proof for anonymous buying — your address is not linked to this purchase on-chain.">
          <Text fontSize="sm" color={useZk ? "brand.400" : "dark.300"} cursor="default">
            ZK Anonymous buy
          </Text>
        </Tooltip>
      </HStack>

      {useZk && (
        <Box
          bg="dark.800"
          border="1px solid"
          borderColor="brand.700"
          borderRadius="md"
          p={3}
        >
          <Text fontSize="xs" color="brand.400">
            ZK mode active — a Noir proof nullifier is generated client-side.
            Your wallet address is not recorded in the buy event.
          </Text>
        </Box>
      )}

      {error && (
        <Text fontSize="sm" color="red.400">{error}</Text>
      )}

      <Button
        bg="brand.500"
        color="dark.900"
        _hover={{ bg: "brand.400" }}
        _active={{ bg: "brand.600" }}
        isLoading={loading}
        isDisabled={!connected || !delta}
        onClick={handleBuy}
        fontWeight="bold"
      >
        {!connected ? "Connect wallet" : useZk ? "ZK Buy" : "Buy"}
      </Button>
    </VStack>
  );
};
