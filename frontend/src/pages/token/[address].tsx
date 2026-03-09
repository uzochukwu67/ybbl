import {
  Alert,
  AlertIcon,
  Badge,
  Box,
  Button,
  Flex,
  Grid,
  Heading,
  HStack,
  Link,
  Spinner,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Text,
  VStack,
} from "@chakra-ui/react";
import { useRouter } from "next/router";
import { useEffect, useState } from "react";
import { useLaunchpad } from "hooks/useLaunchpad";
import { BondingCurveChart } from "components/launchpad/BondingCurveChart";
import { GraduationBar } from "components/launchpad/GraduationBar";
import { TokenStats } from "components/launchpad/TokenStats";
import { BuyWidget } from "components/launchpad/BuyWidget";
import { SellWidget } from "components/launchpad/SellWidget";
import { STARKNET_EXPLORER } from "lib/constants";
import { shortAddr } from "lib/starknetUtils";

interface TokenData {
  supply: bigint;
  reserve: bigint;
  fees: bigint;
  baseAsset: string;
  graduated: boolean;
  nftId: number;
  threshold: bigint;
  maxSupply: bigint;
  curveK: bigint;
}

const STRK = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

const EMPTY: TokenData = {
  supply: 0n,
  reserve: 0n,
  fees: 0n,
  baseAsset: STRK,
  graduated: false,
  nftId: 0,
  threshold: 0n,
  maxSupply: 0n,
  curveK: 0n,
};

const TokenPage = () => {
  const router = useRouter();
  const address = (router.query.address as string) || "";

  const {
    getSupplySold,
    getReserve,
    getFees,
    getBaseAsset,
    isGraduated,
    getEkuboNftId,
    getGradThreshold,
    getMaxSupply,
    getCurveK,
    graduate,
    collectLpFees,
    harvestYield,
    getPendingYield,
    getVesuPrincipal,
    connected,
    loading,
  } = useLaunchpad();

  const [data, setData] = useState<TokenData>(EMPTY);
  const [pendingYield, setPendingYield] = useState<bigint>(0n);
  const [vesuPrincipal, setVesuPrincipal] = useState<bigint>(0n);
  const [fetching, setFetching] = useState(true);
  const [fetchError, setFetchError] = useState("");
  const [lastTx, setLastTx] = useState("");

  const refresh = async () => {
    if (!address) return;
    setFetching(true);
    setFetchError("");
    try {
      const [
        supply,
        reserve,
        fees,
        baseAsset,
        graduated,
        nftId,
        threshold,
        maxSupply,
        curveK,
      ] = await Promise.all([
        getSupplySold(address),
        getReserve(address),
        getFees(address),
        getBaseAsset(address),
        isGraduated(address),
        getEkuboNftId(address),
        getGradThreshold(),
        getMaxSupply(),
        getCurveK(),
      ]);
      setData({
        supply,
        reserve,
        fees,
        baseAsset,
        graduated,
        nftId,
        threshold,
        maxSupply,
        curveK,
      });
      if (graduated) {
        const [py, vp] = await Promise.all([
          getPendingYield(address),
          getVesuPrincipal(address),
        ]);
        setPendingYield(py);
        setVesuPrincipal(vp);
      }
    } catch (e: any) {
      setFetchError("Failed to load token data. Is this a valid YBBC token?");
    } finally {
      setFetching(false);
    }
  };

  useEffect(() => {
    if (address) {
      refresh();
    } else {
      setFetching(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [address]);

  const canGraduate =
    !data.graduated && data.threshold > 0n && data.reserve >= data.threshold;

  const handleGraduate = async () => {
    try {
      const hash = await graduate(address);
      setLastTx(hash);
      setTimeout(() => {
        refresh();
      }, 4000);
    } catch (e: any) {
      setFetchError(e?.message || "Graduate failed");
    }
  };

  const handleCollect = async () => {
    try {
      const hash = await collectLpFees(address);
      setLastTx(hash);
    } catch (e: any) {
      setFetchError(e?.message || "Collect failed");
    }
  };

  const handleBuySuccess = (hash: string) => {
    setLastTx(hash);
    setTimeout(() => {
      refresh();
    }, 4000);
  };

  if (!address) return null;

  return (
    <Box>
      {/* Header */}
      <Flex
        align="center"
        justify="space-between"
        mb={6}
        flexWrap="wrap"
        gap={3}
      >
        <Box>
          <HStack mb={1}>
            <Heading fontSize="xl" color="dark.50">
              Token
            </Heading>
            {data.graduated && (
              <Badge colorScheme="green" variant="subtle">
                Graduated
              </Badge>
            )}
          </HStack>
          <Link
            href={`${STARKNET_EXPLORER}/contract/${address}`}
            isExternal
            fontSize="xs"
            color="brand.400"
            fontFamily="mono"
          >
            {shortAddr(address)} ↗
          </Link>
        </Box>
        {canGraduate && (
          <Button
            bg="green.700"
            color="white"
            _hover={{ bg: "green.600" }}
            size="sm"
            isLoading={loading}
            isDisabled={!connected}
            onClick={handleGraduate}
          >
            Graduate to Ekubo
          </Button>
        )}
        {data.graduated && data.nftId > 0 && (
          <Button
            variant="outline"
            borderColor="dark.600"
            color="dark.200"
            _hover={{ borderColor: "brand.500", color: "brand.400" }}
            size="sm"
            isLoading={loading}
            isDisabled={!connected}
            onClick={handleCollect}
          >
            Collect LP Fees
          </Button>
        )}
      </Flex>

      {fetchError && (
        <Alert
          status="error"
          bg="dark.800"
          borderRadius="lg"
          mb={5}
          border="1px solid"
          borderColor="red.800"
        >
          <AlertIcon color="red.400" />
          <Text fontSize="sm" color="dark.200">
            {fetchError}
          </Text>
        </Alert>
      )}

      {lastTx && (
        <Alert
          status="success"
          bg="dark.800"
          borderRadius="lg"
          mb={5}
          border="1px solid"
          borderColor="green.800"
        >
          <AlertIcon color="green.400" />
          <Text fontSize="sm" color="dark.50">
            Tx submitted:{" "}
            <Link
              href={`${STARKNET_EXPLORER}/tx/${lastTx}`}
              isExternal
              color="brand.400"
            >
              {shortAddr(lastTx)}
            </Link>
          </Text>
        </Alert>
      )}

      {fetching && (
        <Flex justify="center" py={12}>
          <Spinner color="brand.500" size="lg" />
        </Flex>
      )}

      {!fetching && (
        <Grid templateColumns={["1fr", "1fr", "1.4fr 1fr"]} gap={6}>
          {/* Left: Chart + Stats */}
          <VStack align="stretch" spacing={6}>
            <Box
              bg="dark.800"
              border="1px solid"
              borderColor="dark.600"
              borderRadius="xl"
              p={5}
            >
              <BondingCurveChart
                curveK={data.curveK}
                maxSupply={data.maxSupply}
                currentSupply={data.supply}
                gradThreshold={data.threshold}
                reserve={data.reserve}
                width={560}
                height={220}
              />
            </Box>

            <Box
              bg="dark.800"
              border="1px solid"
              borderColor="dark.600"
              borderRadius="xl"
              p={5}
            >
              <GraduationBar
                reserve={data.reserve}
                threshold={data.threshold}
                graduated={data.graduated}
              />
            </Box>

            <TokenStats
              supply={data.supply}
              reserve={data.reserve}
              fees={data.fees}
              curveK={data.curveK}
              maxSupply={data.maxSupply}
              graduated={data.graduated}
              nftId={data.nftId}
            />
          </VStack>

          {/* Right: Trade panel */}
          <Box
            bg="dark.800"
            border="1px solid"
            borderColor="dark.600"
            borderRadius="xl"
            p={5}
          >
            {data.graduated ? (
              <VStack spacing={5} align="stretch">
                <VStack spacing={1} align="center" pt={2}>
                  <Text fontWeight="semibold" color="green.400" fontSize="lg">
                    Token Graduated
                  </Text>
                  <Text fontSize="xs" color="dark.400">
                    Trading live on Ekubo DEX
                  </Text>
                  {data.nftId > 0 && (
                    <Link
                      href="https://app.ekubo.org"
                      isExternal
                      color="brand.400"
                      fontSize="sm"
                    >
                      Trade on Ekubo ↗
                    </Link>
                  )}
                </VStack>

                {/* BTC-yield flywheel panel */}
                <Box
                  bg="dark.900"
                  borderRadius="lg"
                  p={4}
                  border="1px solid"
                  borderColor="dark.600"
                >
                  <Text
                    fontSize="xs"
                    color="dark.300"
                    fontWeight="semibold"
                    mb={3}
                  >
                    BTC YIELD FLYWHEEL
                  </Text>
                  <VStack spacing={3} align="stretch">
                    <HStack justify="space-between" fontSize="sm">
                      <Text color="dark.400">Vesu principal</Text>
                      <Text color="dark.100" fontFamily="mono">
                        {vesuPrincipal > 0n ? vesuPrincipal.toString() : "—"}
                      </Text>
                    </HStack>
                    <HStack justify="space-between" fontSize="sm">
                      <Text color="dark.400">Pending yield</Text>
                      <Text
                        color={pendingYield > 0n ? "green.400" : "dark.400"}
                        fontFamily="mono"
                        fontWeight={pendingYield > 0n ? "bold" : "normal"}
                      >
                        {pendingYield > 0n
                          ? `+${pendingYield.toString()}`
                          : "0"}
                      </Text>
                    </HStack>
                    <Button
                      bg="brand.500"
                      color="dark.900"
                      _hover={{ bg: "brand.400" }}
                      _active={{ bg: "brand.600" }}
                      size="sm"
                      isDisabled={!connected || pendingYield === 0n}
                      isLoading={loading}
                      onClick={async () => {
                        try {
                          const hash = await harvestYield(address);
                          setLastTx(hash);
                          setTimeout(() => {
                            refresh();
                          }, 4000);
                        } catch (e: any) {
                          setFetchError(e?.message || "Harvest failed");
                        }
                      }}
                    >
                      {pendingYield > 0n
                        ? "Harvest Yield → Deepen LP"
                        : "No yield yet"}
                    </Button>
                    <Text fontSize="xs" color="dark.500" textAlign="center">
                      Harvests accrued wBTC yield from Vesu, mints meme tokens
                      at graduation price, and seeds a new Ekubo LP position.
                    </Text>
                  </VStack>
                </Box>
              </VStack>
            ) : (
              <Tabs variant="unstyled" colorScheme="orange">
                <TabList bg="dark.900" borderRadius="lg" p={1} mb={5}>
                  <Tab
                    flex="1"
                    borderRadius="md"
                    fontSize="sm"
                    color="dark.300"
                    _selected={{
                      bg: "brand.500",
                      color: "dark.900",
                      fontWeight: "bold",
                    }}
                  >
                    Buy
                  </Tab>
                  <Tab
                    flex="1"
                    borderRadius="md"
                    fontSize="sm"
                    color="dark.300"
                    _selected={{
                      bg: "dark.700",
                      color: "red.400",
                      fontWeight: "bold",
                    }}
                  >
                    Sell
                  </Tab>
                </TabList>
                <TabPanels>
                  <TabPanel p={0}>
                    <BuyWidget
                      token={address}
                      baseAsset={data.baseAsset}
                      curveK={data.curveK}
                      supply={data.supply}
                      onSuccess={handleBuySuccess}
                    />
                  </TabPanel>
                  <TabPanel p={0}>
                    <SellWidget
                      token={address}
                      curveK={data.curveK}
                      supply={data.supply}
                      onSuccess={handleBuySuccess}
                    />
                  </TabPanel>
                </TabPanels>
              </Tabs>
            )}
          </Box>
        </Grid>
      )}
    </Box>
  );
};

export default TokenPage;
