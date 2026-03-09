import { Box, Flex, Text, Tooltip } from "@chakra-ui/react";
import { gradProgress, formatUnits } from "lib/starknetUtils";

interface Props {
  reserve: bigint;
  threshold: bigint;
  graduated: boolean;
}

export const GraduationBar = ({ reserve, threshold, graduated }: Props) => {
  const pct = gradProgress(reserve, threshold);

  return (
    <Box>
      <Flex justify="space-between" mb={1}>
        <Text fontSize="xs" color="dark.300">
          {graduated ? "Graduated to Ekubo" : "Graduation progress"}
        </Text>
        <Tooltip
          label={`${formatUnits(reserve)} / ${formatUnits(
            threshold
          )} base asset`}
        >
          <Text
            fontSize="xs"
            color={graduated ? "green.400" : "brand.400"}
            cursor="default"
          >
            {graduated ? "100%" : `${pct.toFixed(1)}%`}
          </Text>
        </Tooltip>
      </Flex>
      <Box bg="dark.700" borderRadius="full" h="6px" overflow="hidden">
        <Box
          bg={graduated ? "green.400" : "brand.500"}
          h="full"
          borderRadius="full"
          w={`${Math.max(pct, graduated ? 100 : 0)}%`}
          transition="width 0.4s ease"
        />
      </Box>
    </Box>
  );
};
