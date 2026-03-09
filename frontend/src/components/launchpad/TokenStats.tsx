import { Box, SimpleGrid, Text } from "@chakra-ui/react";
import { formatUnits, spotPrice } from "lib/starknetUtils";

interface Props {
  supply: bigint;
  reserve: bigint;
  fees: bigint;
  curveK: bigint;
  maxSupply: bigint;
  graduated: boolean;
  nftId: number;
}

const Stat = ({ label, value }: { label: string; value: string }) => (
  <Box
    bg="dark.800"
    borderRadius="lg"
    p={4}
    border="1px solid"
    borderColor="dark.600"
  >
    <Text fontSize="xs" color="dark.300" mb={1}>
      {label}
    </Text>
    <Text fontSize="md" fontWeight="semibold" color="dark.50">
      {value}
    </Text>
  </Box>
);

export const TokenStats = ({
  supply,
  reserve,
  fees,
  curveK,
  maxSupply,
  graduated,
  nftId,
}: Props) => {
  const spot = curveK > 0n ? spotPrice(curveK, supply) : 0n;
  const supplyPct =
    maxSupply > 0n
      ? `${((Number(supply) / Number(maxSupply)) * 100).toFixed(2)}%`
      : `${formatUnits(supply, 0)} tokens`;

  return (
    <SimpleGrid columns={[2, 3]} spacing={3}>
      <Stat label="Spot Price" value={`${formatUnits(spot)} / token`} />
      <Stat label="Supply Sold" value={supplyPct} />
      <Stat label="Reserve (base)" value={formatUnits(reserve)} />
      <Stat label="Accrued Fees" value={formatUnits(fees)} />
      <Stat
        label="Status"
        value={graduated ? (nftId ? `LP #${nftId}` : "Graduated") : "Trading"}
      />
      <Stat
        label="Max Supply"
        value={maxSupply > 0n ? formatUnits(maxSupply, 0) : "Unlimited"}
      />
    </SimpleGrid>
  );
};
