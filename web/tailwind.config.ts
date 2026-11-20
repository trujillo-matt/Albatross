import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // The brand green is the iOS app's own (#243627). Everything else is a warm neutral.
        brand: { DEFAULT: "#243627", hover: "#2f4733", light: "#e8efe9", accent: "#3f6b48", tint: "#9fc3a7" },
        paper: "#f4efe4",
        hair: "rgba(28, 25, 23, 0.10)",
        warn: "#a16207",
        bad: "#b91c1c",
      },
      fontFamily: {
        // Serif is for large titles and score numerals only. Everything else is sans.
        sans: ['"Inter Variable"', "ui-sans-serif", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"],
        serif: ['"Newsreader Variable"', "Georgia", "Times New Roman", "serif"],
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "Consolas", "monospace"],
      },
      transitionTimingFunction: { out: "cubic-bezier(0.22, 1, 0.36, 1)" },
      transitionDuration: { 150: "150ms" },
    },
  },
  plugins: [],
};
export default config;
