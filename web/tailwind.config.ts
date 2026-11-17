import type { Config } from "tailwindcss";
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: { brand: { DEFAULT: "#243627", light: "#e8efe9", accent: "#3f6b48" } },
      fontFamily: { serif: ["Baskerville", "Georgia", "serif"] },
    },
  },
  plugins: [],
};
export default config;
