import { Box, Flex, HStack, Link as CLink, Text } from "@chakra-ui/react";
import Link from "next/link";
import { useRouter } from "next/router";

import { WalletConnect } from "components/wallet";

const NAV = [
  { label: "Explore", href: "/explore" },
  { label: "Launch", href: "/launch" },
];

const Header = () => {
  const router = useRouter();

  return (
    <Flex
      as="header"
      width="full"
      align="center"
      py={4}
      borderBottom="1px solid"
      borderColor="dark.700"
    >
      <Link href="/" passHref>
        <Box as="a" display="flex" alignItems="center" _hover={{ textDecoration: "none" }}>
          <Box
            w={7}
            h={7}
            bg="brand.500"
            borderRadius="md"
            display="flex"
            alignItems="center"
            justifyContent="center"
            mr={2}
          >
            <Text fontSize="sm" fontWeight="bold" color="dark.900">B</Text>
          </Box>
          <Text fontWeight="bold" fontSize="lg" color="dark.50">
            YBBC
          </Text>
        </Box>
      </Link>

      <HStack ml={8} spacing={6}>
        {NAV.map((n) => (
          <Link key={n.href} href={n.href} passHref>
            <CLink
              fontSize="sm"
              fontWeight={router.pathname === n.href ? "semibold" : "normal"}
              color={router.pathname === n.href ? "brand.500" : "dark.200"}
              _hover={{ color: "brand.400", textDecoration: "none" }}
            >
              {n.label}
            </CLink>
          </Link>
        ))}
      </HStack>

      <Box marginLeft="auto">
        <WalletConnect />
      </Box>
    </Flex>
  );
};

export default Header;
