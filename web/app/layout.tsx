import "./globals.css";
import type { Metadata, Viewport } from "next";
import RegisterSW from "@/components/RegisterSW";

export const metadata: Metadata = { title: "Albatross Tournaments", description: "Log scores and run your golf tournament.",
  manifest: "/manifest.webmanifest", icons: { icon: "/icon-192.png", apple: "/icon-192.png" } };
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#243627" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body><RegisterSW /><main className="mx-auto max-w-xl px-4 py-6">{children}</main></body>
    </html>
  );
}
