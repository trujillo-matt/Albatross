import { Dot } from "./ui";

/**
 * Landing hero visual: what a player sees, drawn in code with plausible data (Pebble Beach front nine pars).
 * Printed-scorecard notation: a ring around a birdie, a square around a bogey.
 */
const PARS = [4, 5, 4, 4, 3, 5, 3, 4, 4];
const SCORES = [4, 6, 4, 3, 3, 5, 4, 4, 5];

function Mark({ score, par }: { score: number; par: number }) {
  const d = score - par;
  const shape = d < 0 ? "rounded-full ring-1 ring-stone-700" : d > 0 ? "rounded-sm ring-1 ring-stone-700" : "";
  return <span className={`num inline-flex h-7 w-7 items-center justify-center text-lg ${shape}`}>{score}</span>;
}

export default function ScorecardPreview() {
  const out = SCORES.reduce((a, b) => a + b, 0);
  const par = PARS.reduce((a, b) => a + b, 0);
  return (
    <figure className="m-0" aria-label="A scorecard as players see it">
      <div className="overflow-hidden rounded-t-2xl bg-white ring-1 ring-hair md:rounded-2xl">
        <div className="flex items-center justify-between border-b border-hair px-5 py-4">
          <div>
            <div className="text-sm text-stone-900">Pebble Beach Golf Links</div>
            <div className="muted">Match 1 · Stroke play</div>
          </div>
          <span className="inline-flex items-center gap-2 text-sm text-stone-600"><Dot tone="live" />Synced</span>
        </div>
        <div className="overflow-x-auto px-5 py-4">
          <table className="w-full min-w-[22rem] border-collapse text-center">
            <thead>
              <tr className="text-xs text-stone-500">
                <th className="py-2 pr-3 text-left font-normal">Hole</th>
                {PARS.map((_, i) => <th key={i} className="num py-2 font-normal">{i + 1}</th>)}
                <th className="py-2 pl-3 text-right font-normal">Out</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-t border-hair text-stone-500">
                <td className="py-3 pr-3 text-left text-xs">Par</td>
                {PARS.map((p, i) => <td key={i} className="num text-base">{p}</td>)}
                <td className="num pl-3 text-right text-base">{par}</td>
              </tr>
              <tr className="border-t border-hair">
                <td className="py-3 pr-3 text-left text-xs text-stone-500">Dana</td>
                {SCORES.map((s, i) => <td key={i}><Mark score={s} par={PARS[i]} /></td>)}
                <td className="num pl-3 text-right text-xl text-brand">{out}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </figure>
  );
}
