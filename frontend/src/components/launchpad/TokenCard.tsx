import { Badge, Box, Button, HStack, Text, VStack } from "@chakra-ui/react";
import Link from "next/link";
import { StoredToken } from "hooks/useTokenStorage";
import { GraduationBar } from "./GraduationBar";


// Normalize a Starknet address to full 66-char hex (0x + 64 hex digits)
const padAddr = (addr: string): string => {
  if (!addr?.startsWith("0x")) return addr ?? "";
  return "0x" + addr.slice(2).padStart(64, "0");
};

// Map known base asset addresses → symbol + decimals for price display
const ASSET_META: Record<string, { symbol: string; decimals: number }> = {
  "0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac": { symbol: "wBTC", decimals: 8 },
  "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7": { symbol: "ETH", decimals: 18 },
  "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d": { symbol: "STRK", decimals: 18 },
  "0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8": { symbol: "USDC", decimals: 6 },
};

// Format price with enough precision to show micro-amounts
function formatPrice(raw: bigint, decimals: number): string {
  if (raw === 0n) return "—";
  const scale = BigInt(10 ** decimals);
  const whole = raw / scale;
  const frac = raw % scale;
  if (whole > 0n) {
    const fracStr = frac.toString().padStart(decimals, "0").replace(/0+$/, "");
    return fracStr ? `${whole}.${fracStr.slice(0, 6)}` : whole.toString();
  }
  // Show up to 10 significant digits for sub-1 amounts
  const fracStr = frac.toString().padStart(decimals, "0");
  const nonZero = fracStr.search(/[^0]/);
  if (nonZero === -1) return "0";
  return `0.${fracStr.slice(0, nonZero + 6).replace(/0+$/, "")}`;
}

interface Props {
  token: StoredToken;
  reserve?: bigint;
  threshold?: bigint;
  graduated?: boolean;
  spotPrice?: bigint;
}

export const TokenCard = ({
  token,
  reserve = 0n,
  threshold = 0n,
  graduated = false,
  spotPrice = 0n,
}: Props) => {
  const meta = ASSET_META[padAddr(token.baseAsset)] ?? { symbol: "STRK", decimals: 18 };
  const priceStr = formatPrice(spotPrice, meta.decimals);

  return (
    <Box
      bg="dark.800"
      border="1px solid"
      borderColor="dark.600"
      borderRadius="xl"
      p={5}
      _hover={{
        borderColor: "brand.500",
        transition: "all 0.15s ease",
      }}
      transition="all 0.15s ease"
    >
      <VStack align="stretch" spacing={4}>
        {/* Header */}
        <HStack justify="space-between">
          <HStack>
            <Box
              w={9}
              h={9}
              bg="brand.900"
              borderRadius="full"
              border="2px solid"
              borderColor="brand.500"
              display="flex"
              alignItems="center"
              justifyContent="center"
            >
              <Text fontSize="sm" fontWeight="bold" color="brand.400">
                {token.symbol.slice(0, 2)}
              </Text>
            </Box>
            <VStack align="start" spacing={0}>
              <Text fontWeight="semibold" color="dark.50" fontSize="sm">
                {token.name}
              </Text>
              <Text fontSize="xs" color="dark.400">
                {token.symbol}
              </Text>
            </VStack>
          </HStack>
          {graduated && (
            <Badge colorScheme="green" variant="subtle" fontSize="xs">
              Graduated
            </Badge>
          )}
        </HStack>

        {/* Spot price */}
        <HStack justify="space-between">
          <Text fontSize="xs" color="dark.400">
            Spot price
          </Text>
          <Text fontSize="sm" fontWeight="semibold" color="brand.300" fontFamily="mono">
            {priceStr} {meta.symbol}
          </Text>
        </HStack>

        <GraduationBar
          reserve={reserve}
          threshold={threshold}
          graduated={graduated}
        />

        {/* Actions */}
        <HStack spacing={2}>
          <Link href={`/token/${token.address}`} passHref style={{ flex: 1 }}>
            <Button
              as="a"
              w="full"
              bg="brand.500"
              color="dark.900"
              _hover={{ bg: "brand.400" }}
              fontWeight="bold"
              size="sm"
              isDisabled={graduated}
            >
              Buy
            </Button>
          </Link>
          <Link href={`/token/${token.address}`} passHref>
            <Button
              as="a"
              variant="outline"
              borderColor="dark.600"
              color="dark.300"
              _hover={{ borderColor: "dark.400", color: "dark.100" }}
              size="sm"
            >
              View
            </Button>
          </Link>
        </HStack>

        <Text fontSize="xs" color="dark.500">
          {new Date(token.launchedAt).toLocaleDateString()}
        </Text>
      </VStack>
    </Box>
  );
};
