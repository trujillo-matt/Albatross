import { formatCode } from "@/lib/code";

/**
 * The printed player card: the one object players physically hold. Credit-card proportions, paper stock,
 * a double rule like a scorecard header, the code set large in mono. Prints four to a page.
 */
export default function CodeCard({ tournament, player, code, host }: { tournament: string; player: string; code: string; host: string }) {
  return (
    <div data-code-card data-player={player} className="break-inside-avoid rounded-xl bg-paper p-5 ring-1 ring-hair print:rounded-none print:ring-stone-400">
      <div className="flex items-center gap-2">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/icon-192.png" alt="" className="h-6 w-6 object-contain mix-blend-multiply" />
        <span className="text-xs text-stone-600">Albatross Tournaments</span>
      </div>
      <div className="mt-4 border-y-4 border-double border-stone-300 py-3">
        <div className="font-serif text-2xl leading-tight text-brand">{tournament}</div>
        <div className="mt-1 text-sm text-stone-700">{player}</div>
      </div>
      <div className="mt-4 font-mono text-3xl tracking-widest text-stone-900">{formatCode(code)}</div>
      <div className="mt-3 text-xs text-stone-600">Enter this code at {host}/join</div>
    </div>
  );
}
