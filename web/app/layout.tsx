import "./globals.css";
import type { Metadata, Viewport } from "next";
import RegisterSW from "@/components/RegisterSW";
import ThemeToggle from "@/components/ThemeToggle";

// Runs before the page paints so a saved Light or Dark choice never flashes the other one.
const applyTheme = `try{var t=localStorage.getItem("albatross-theme");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch(e){}`;

export const metadata: Metadata = { title: "Albatross Tournaments", description: "Log scores and run your golf tournament.",
  manifest: "/manifest.webmanifest", icons: { icon: "/icon-192.png", apple: "/icon-192.png" } };
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#243627" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head><script dangerouslySetInnerHTML={{ __html: applyTheme }} /></head>
      <body><RegisterSW /><main className="px-4 py-6">{children}</main><ThemeToggle /></body>
    </html>
  );
}
