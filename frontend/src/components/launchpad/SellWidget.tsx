import {
  Box,
  Button,
  FormControl,
  FormLabel,
  HStack,
  Input,
  Text,
  VStack,
} from "@chakra-ui/react";
import { useCallback, useState } from "react";
import { useLaunchpad } from "hooks/useLaunchpad";
import {
  sellPayout,
  withoutFee,
  parseUnits,
  formatUnits,
} from "lib/starknetUtils";

interface Props {
  token: string;
  curveK: bigint;
  supply: bigint;
  onSuccess?: (txHash: string) => void;
}

export const SellWidget = ({ token, curveK, supply, onSuccess }: Props) => {
  const { sell, loading, connected } = useLaunchpad();
  const [amount, setAmount] = useState("");
  const [slippage, setSlippage] = useState("1");
  const [error, setError] = useState("");

  const delta = parseUnits(amount, 0);
  const payout =
    delta > 0n && delta <= supply ? sellPayout(curveK, supply, delta) : 0n;
  const netPayout = withoutFee(payout);
  const slippageBps = Math.floor(parseFloat(slippage || "1") * 100);
  const minPayout = netPayout - (netPayout * BigInt(slippageBps)) / 10000n;

  const handleSell = useCallback(async () => {
    setError("");
    if (!delta || delta === 0n) {
      setError("Enter an amount");
      return;
    }
    if (delta > supply) {
      setError("Exceeds supply sold");
      return;
    }
    try {
      const txHash = await sell(token, delta, minPayout);
      setAmount("");
      onSuccess?.(txHash);
    } catch (e: any) {
      setError(e?.message || "Transaction failed");
    }
  }, [delta, minPayout, supply, token, sell, onSuccess]);

  return (
    <VStack spacing={4} align="stretch">
      <FormControl>
        <FormLabel fontSize="sm" color="dark.200">
          Amount to sell (tokens)
        </FormLabel>
        <Input
          value={amount}
          onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))}
          placeholder="50"
          bg="dark.800"
          border="1px solid"
          borderColor="dark.600"
          _focus={{ borderColor: "red.400", boxShadow: "none" }}
          _hover={{ borderColor: "dark.500" }}
          color="dark.50"
        />
      </FormControl>

      {delta > 0n && delta <= supply && (
        <Box
          bg="dark.800"
          borderRadius="md"
          p={3}
          border="1px solid"
          borderColor="dark.600"
        >
          <HStack justify="space-between">
            <Text fontSize="sm" color="dark.300">
              You receive
            </Text>
            <Text fontSize="sm" color="green.400" fontWeight="semibold">
              {formatUnits(netPayout)} base
            </Text>
          </HStack>
          <HStack justify="space-between" mt={1}>
            <Text fontSize="xs" color="dark.400">
              Fee (1%)
            </Text>
            <Text fontSize="xs" color="dark.400">
              -{formatUnits(payout - netPayout)}
            </Text>
          </HStack>
        </Box>
      )}

      <FormControl>
        <FormLabel fontSize="sm" color="dark.200">
          Slippage %
        </FormLabel>
        <Input
          value={slippage}
          onChange={(e) => setSlippage(e.target.value)}
          w="100px"
          bg="dark.800"
          border="1px solid"
          borderColor="dark.600"
          _focus={{ borderColor: "red.400", boxShadow: "none" }}
          color="dark.50"
          size="sm"
        />
      </FormControl>

      {error && (
        <Text fontSize="sm" color="red.400">
          {error}
        </Text>
      )}

      <Button
        bg="dark.700"
        color="red.400"
        border="1px solid"
        borderColor="red.800"
        _hover={{ bg: "red.900", borderColor: "red.600" }}
        isLoading={loading}
        isDisabled={!connected || !delta || delta > supply}
        onClick={handleSell}
        fontWeight="bold"
      >
        {!connected ? "Connect wallet" : "Sell"}
      </Button>
    </VStack>
  );
};
