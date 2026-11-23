import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    // The three text sizes, size / line height: 14/18, 16/20 and 18/22. Larger sizes are for display titles and numerals only.
    fontSize: {
      xs: ["14px", "18px"],
      sm: ["14px", "18px"],
      base: ["16px", "20px"],
      lg: ["18px", "22px"],
      xl: ["20px", "26px"],
      "2xl": ["24px", "30px"],
      "3xl": ["30px", "36px"],
      "4xl": ["36px", "40px"],
      "5xl": ["48px", "1"],
      "6xl": ["60px", "1"],
      "7xl": ["72px", "1"],
    },
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
