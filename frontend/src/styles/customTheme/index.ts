import { extendTheme } from "@chakra-ui/react";

import colors from "./colors";
import Button from "./components/button";
import fonts from "./fonts";

const customTheme = extendTheme({
  config: {
    initialColorMode: "dark",
    useSystemColorMode: false,
  },
  fonts,
  colors,
  styles: {
    global: {
      body: {
        bg: "dark.900",
        color: "dark.50",
      },
    },
  },
  components: {
    Button,
  },
});

export default customTheme;
