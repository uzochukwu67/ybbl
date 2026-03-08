import { Flex, HStack, Link, Text } from "@chakra-ui/react";

const Footer = () => {
  return (
    <Flex
      as="footer"
      width="full"
      align="center"
      justify="space-between"
      py={4}
      borderTop="1px solid"
      borderColor="dark.700"
      mt={8}
    >
      <Text fontSize="sm" color="dark.300">
        YBBC — Yield-Bearing Bonding Curve on Starknet
      </Text>
      <HStack spacing={4} fontSize="sm" color="dark.300">
        <Link href="https://ekubo.org" isExternal _hover={{ color: "brand.500", textDecoration: "none" }}>
          Powered by Ekubo
        </Link>
        <Text>·</Text>
        <Link href="https://vesu.xyz" isExternal _hover={{ color: "brand.500", textDecoration: "none" }}>
          Yield via Vesu
        </Link>
      </HStack>
    </Flex>
  );
};

export default Footer;
