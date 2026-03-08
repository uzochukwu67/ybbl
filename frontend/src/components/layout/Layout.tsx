import { Box } from "@chakra-ui/react";
import { ReactNode } from "react";

import { Footer, Header } from ".";

type LayoutProps = {
  children: ReactNode;
};

const Layout = ({ children }: LayoutProps) => {
  return (
    <Box margin="0 auto" h="100%" maxWidth={1200} transition="0.3s ease-out">
      <Box px={[4, 6, 8]} h="full" d="flex" flexDirection="column">
        <Header />
        <Box flex="1 1 auto" as="main" py={8}>
          {children}
        </Box>
        <Footer />
      </Box>
    </Box>
  );
};

export default Layout;
