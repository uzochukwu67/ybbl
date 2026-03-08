import {
  Box,
  Button,
  Flex,
  Grid,
  Heading,
  HStack,
  SimpleGrid,
  Text,
  VStack,
} from "@chakra-ui/react";
import Link from "next/link";

const Feature = ({
  icon,
  title,
  desc,
}: {
  icon: string;
  title: string;
  desc: string;
}) => (
  <Box
    bg="dark.800"
    border="1px solid"
    borderColor="dark.600"
    borderRadius="xl"
    p={6}
    _hover={{ borderColor: "brand.700" }}
    transition="border-color 0.2s"
  >
    <Text fontSize="2xl" mb={3}>{icon}</Text>
    <Text fontWeight="semibold" color="dark.50" mb={2}>
      {title}
    </Text>
    <Text fontSize="sm" color="dark.300" lineHeight="tall">
      {desc}
    </Text>
  </Box>
);

const Step = ({
  n,
  title,
  desc,
}: {
  n: string;
  title: string;
  desc: string;
}) => (
  <HStack align="start" spacing={4}>
    <Box
      w={8}
      h={8}
      bg="brand.500"
      borderRadius="md"
      display="flex"
      alignItems="center"
      justifyContent="center"
      flexShrink={0}
    >
      <Text fontSize="sm" fontWeight="bold" color="dark.900">{n}</Text>
    </Box>
    <Box>
      <Text fontWeight="semibold" color="dark.50" mb={1}>{title}</Text>
      <Text fontSize="sm" color="dark.300">{desc}</Text>
    </Box>
  </HStack>
);

const Home = () => {
  return (
    <Box>
      {/* ── Hero ─────────────────────────────────────────────────────────── */}
      <Flex
        direction="column"
        align="center"
        textAlign="center"
        py={[12, 20]}
        px={4}
      >
        <Box
          bg="brand.900"
          border="1px solid"
          borderColor="brand.700"
          borderRadius="full"
          px={4}
          py={1}
          mb={6}
        >
          <Text fontSize="xs" color="brand.400" fontWeight="semibold" letterSpacing="wide">
            ZK-PRIVATE · STARKNET · BTC-NATIVE
          </Text>
        </Box>

        <Heading
          as="h1"
          fontSize={["3xl", "5xl", "6xl"]}
          fontWeight="bold"
          color="dark.50"
          lineHeight="tight"
          mb={6}
          maxW="800px"
        >
          The first{" "}
          <Box as="span" color="brand.500">
            BTC-yield
          </Box>{" "}
          bonding curve launchpad with{" "}
          <Box as="span" color="brand.500">
            ZK privacy
          </Box>
        </Heading>

        <Text
          fontSize={["md", "lg"]}
          color="dark.300"
          maxW="600px"
          mb={10}
          lineHeight="tall"
        >
          Launch tokens backed by stBTC. Trade on a fair quadratic bonding curve.
          Graduate to Ekubo DEX with protocol-owned yield earning on Vesu.
          Buy anonymously with Noir zero-knowledge proofs.
        </Text>

        <HStack spacing={4}>
          <Link href="/launch" passHref>
            <Button
              as="a"
              bg="brand.500"
              color="dark.900"
              _hover={{ bg: "brand.400" }}
              size="lg"
              fontWeight="bold"
              px={8}
            >
              Launch a Token
            </Button>
          </Link>
          <Link href="/explore" passHref>
            <Button
              as="a"
              variant="outline"
              borderColor="dark.600"
              color="dark.200"
              _hover={{ borderColor: "brand.500", color: "brand.400" }}
              size="lg"
            >
              Explore Tokens
            </Button>
          </Link>
        </HStack>
      </Flex>

      {/* ── Stats bar ─────────────────────────────────────────────────────── */}
      <SimpleGrid
        columns={[2, 4]}
        spacing={4}
        mb={16}
        px={2}
        bg="dark.800"
        border="1px solid"
        borderColor="dark.600"
        borderRadius="2xl"
        p={6}
      >
        {[
          { label: "Bonding curve formula", value: "K·(2S+Δ)·Δ" },
          { label: "LP fee tier (Ekubo)", value: "0.3%" },
          { label: "Protocol fee", value: "1%" },
          { label: "ZK proof system", value: "Noir / Garaga" },
        ].map((s) => (
          <Box key={s.label} textAlign="center">
            <Text fontWeight="bold" fontSize="lg" color="brand.400">
              {s.value}
            </Text>
            <Text fontSize="xs" color="dark.400" mt={1}>
              {s.label}
            </Text>
          </Box>
        ))}
      </SimpleGrid>

      {/* ── Feature grid ──────────────────────────────────────────────────── */}
      <Box mb={16}>
        <Heading fontSize="2xl" color="dark.50" mb={8} textAlign="center">
          Built different
        </Heading>
        <Grid templateColumns={["1fr", "1fr 1fr", "repeat(3, 1fr)"]} gap={6}>
          <Feature
            icon="₿"
            title="BTC-native yield"
            desc="Use stBTC as the base asset. Every token on the launchpad is backed by Bitcoin yield. Protocol-owned reserves flow into Vesu to earn real BTC yield for the community."
          />
          <Feature
            icon="🔒"
            title="ZK anonymous buys"
            desc="Buy tokens privately using Noir zero-knowledge proofs verified on-chain via Garaga. Your wallet address is not linked to the purchase — true on-chain privacy on Starknet."
          />
          <Feature
            icon="📈"
            title="Fair bonding curve"
            desc="Quadratic pricing means early buyers get the best price and the curve is always predictable. No rugs, no presales, no VCs — just math. Graduate to Ekubo at the correct market price."
          />
          <Feature
            icon="💧"
            title="Auto-LP graduation"
            desc="When the reserve hits the graduation threshold, protocol fees automatically seed an Ekubo full-range LP position at the exact graduation price ratio."
          />
          <Feature
            icon="⚡"
            title="Starknet scale"
            desc="Sub-cent fees, instant finality, Cairo's provable computation. Every trade is cheap enough to be meaningful. Every proof is native to the chain."
          />
          <Feature
            icon="🏛"
            title="Protocol-owned yield"
            desc="Post-graduation, reserves are deployed to Vesu — Starknet's leading lending protocol — generating continuous yield that belongs to the community, not VCs."
          />
        </Grid>
      </Box>

      {/* ── How it works ──────────────────────────────────────────────────── */}
      <Box mb={16}>
        <Heading fontSize="2xl" color="dark.50" mb={8} textAlign="center">
          How it works
        </Heading>
        <Grid templateColumns={["1fr", "1fr 1fr"]} gap={8}>
          <VStack align="stretch" spacing={6}>
            <Text fontWeight="semibold" color="brand.400" fontSize="sm" letterSpacing="wide">
              FOR LAUNCHERS
            </Text>
            <Step
              n="1"
              title="Deploy your token"
              desc="Choose a name, symbol, and base asset (stBTC or any ERC-20). Your token is live instantly with no presale or team allocation."
            />
            <Step
              n="2"
              title="Community trades the curve"
              desc="Buyers purchase on the quadratic bonding curve. Price rises automatically as more tokens are sold. 1% of every trade accumulates as protocol fees."
            />
            <Step
              n="3"
              title="Graduate to Ekubo"
              desc="When reserves hit the threshold, your token graduates automatically. Fees seed an Ekubo LP and reserves earn yield on Vesu."
            />
          </VStack>
          <VStack align="stretch" spacing={6}>
            <Text fontWeight="semibold" color="brand.400" fontSize="sm" letterSpacing="wide">
              FOR TRADERS
            </Text>
            <Step
              n="1"
              title="Buy early, buy cheap"
              desc="The bonding curve ensures early buyers always get the lowest price. No whitelist, no FCFS — just connect wallet and buy."
            />
            <Step
              n="2"
              title="Go anonymous with ZK"
              desc="Toggle ZK mode to generate a Noir proof nullifier. Your purchase is processed on-chain with no link to your wallet address."
            />
            <Step
              n="3"
              title="Sell anytime before graduation"
              desc="The bonding curve guarantees instant liquidity. Sell back at any time for the current curve price. After graduation, trade on Ekubo."
            />
          </VStack>
        </Grid>
      </Box>

      {/* ── CTA ───────────────────────────────────────────────────────────── */}
      <Box
        bg="dark.800"
        border="1px solid"
        borderColor="brand.800"
        borderRadius="2xl"
        p={[8, 12]}
        textAlign="center"
        mb={8}
      >
        <Heading fontSize={["xl", "2xl"]} color="dark.50" mb={4}>
          Ready to launch the next BTC-native memecoin?
        </Heading>
        <Text color="dark.300" mb={8} maxW="500px" mx="auto">
          Permissionless, fair, private. YBBC is the first launchpad that makes
          Bitcoin yield the default base asset on Starknet.
        </Text>
        <Link href="/launch" passHref>
          <Button
            as="a"
            bg="brand.500"
            color="dark.900"
            _hover={{ bg: "brand.400" }}
            size="lg"
            fontWeight="bold"
            px={10}
          >
            Launch now →
          </Button>
        </Link>
      </Box>
    </Box>
  );
};

export default Home;
