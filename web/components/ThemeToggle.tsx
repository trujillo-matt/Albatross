"use client";
import { useEffect, useState } from "react";

type Choice = "system" | "light" | "dark";
const NEXT: Record<Choice, Choice> = { system: "light", light: "dark", dark: "system" };
const LABEL: Record<Choice, string> = { system: "Match device", light: "Light", dark: "Dark" };

/** Light, dark, or follow the device. The choice is remembered in this browser. */
export default function ThemeToggle() {
  const [choice, setChoice] = useState<Choice>("system");
  useEffect(() => {
    try {
      const saved = localStorage.getItem("albatross-theme");
      if (saved === "light" || saved === "dark") setChoice(saved);
    } catch { /* storage unavailable: stay on the device setting */ }
  }, []);

  const change = () => {
    const next = NEXT[choice];
    setChoice(next);
    try {
      if (next === "system") { localStorage.removeItem("albatross-theme"); delete document.documentElement.dataset.theme; }
      else { localStorage.setItem("albatross-theme", next); document.documentElement.dataset.theme = next; }
    } catch { /* the choice still applies until the page closes */ }
  };

  return (
    <button type="button" onClick={change} aria-label={`Colour mode: ${LABEL[choice]}. Change`}
      className="btn-ghost fixed bottom-4 right-4 z-10 !h-11 shadow-sm print:hidden">
      {LABEL[choice]}
    </button>
  );
}
