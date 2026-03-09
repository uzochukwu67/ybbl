import { Badge, Box, HStack, Text, VStack } from "@chakra-ui/react";
import Link from "next/link";
import { StoredToken } from "hooks/useTokenStorage";
import { GraduationBar } from "./GraduationBar";

interface Props {
  token: StoredToken;
  reserve?: bigint;
  threshold?: bigint;
  graduated?: boolean;
}

export const TokenCard = ({
  token,
  reserve = 0n,
  threshold = 0n,
  graduated = false,
}: Props) => {
  return (
    <Link href={`/token/${token.address}`} passHref>
      <Box
        as="a"
        display="block"
        bg="dark.800"
        border="1px solid"
        borderColor="dark.600"
        borderRadius="xl"
        p={5}
        _hover={{
          borderColor: "brand.500",
          textDecoration: "none",
          transform: "translateY(-2px)",
          transition: "all 0.15s ease",
        }}
        transition="all 0.15s ease"
      >
        <VStack align="stretch" spacing={4}>
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

          <GraduationBar
            reserve={reserve}
            threshold={threshold}
            graduated={graduated}
          />

          <Text fontSize="xs" color="dark.400">
            {new Date(token.launchedAt).toLocaleDateString()}
          </Text>
        </VStack>
      </Box>
    </Link>
  );
};
