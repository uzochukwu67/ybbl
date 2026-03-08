import { DeepPartial, Theme } from "@chakra-ui/react";

/** BTC orange — primary brand color */
const extendedColors: DeepPartial<
  Record<string, Theme["colors"]["blackAlpha"]>
> = {
  brand: {
    50:  "#fff7eb",
    100: "#fee9c4",
    200: "#fed08a",
    300: "#fdb44f",
    400: "#fb9b24",
    500: "#F7931A", // BTC orange
    600: "#d97706",
    700: "#b45309",
    800: "#92400e",
    900: "#78350f",
  },
  dark: {
    50:  "#f2f2f3",
    100: "#d8d8db",
    200: "#b0b0b5",
    300: "#88888f",
    400: "#606069",
    500: "#3c3c47",
    600: "#28282f",
    700: "#1c1c22",
    800: "#131318",
    900: "#0d0d12",
  },
};

const overridenChakraColors: DeepPartial<Theme["colors"]> = {};

const colors = {
  ...overridenChakraColors,
  ...extendedColors,
};

export default colors;
