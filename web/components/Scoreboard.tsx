/**
 * The standings moment: a clubhouse scoreboard. Dark brand panel, large serif tabular numerals, the leader
 * in full paper white and the other side quieter, a thin progress rule toward the points needed to win.
 */
interface Props {
  teams: [{ name: string; points: number; color?: string } | undefined, { name: string; points: number; color?: string } | undefined];
  toWin: number;
  complete?: boolean;
}

const fmt = (n: number) => n.toFixed(1);

export default function Scoreboard({ teams, toWin, complete = false }: Props) {
  const [a, b] = teams;
  if (!a || !b) return null;
  const lead = a.points === b.points ? null : a.points > b.points ? a : b;
  const diff = Math.abs(a.points - b.points);
  const side = (t: { name: string; points: number; color?: string }) => {
    const isLead = lead === t;
    return (
      <div className="min-w-0 flex-1 text-center">
        <div className={`truncate text-sm ${isLead ? "text-paper" : "text-paper/60"}`}>{t.color && <span aria-hidden className="mr-2 inline-block h-2.5 w-2.5 rounded-full align-[0px] ring-1 ring-paper/40" style={{ backgroundColor: t.color }} />}{t.name}</div>
        <div className={`num text-7xl leading-none ${isLead ? "text-paper" : "text-paper/55"}`}>{fmt(t.points)}</div>
        <div className="mx-auto mt-4 h-1 w-24 overflow-hidden rounded-full bg-paper/15" role="img"
          aria-label={`${t.name}: ${fmt(t.points)} of ${fmt(toWin)} points needed`}>
          <div className={`h-full origin-left rounded-full transition-transform duration-500 ease-out ${t.color ? "" : isLead ? "bg-brand-tint" : "bg-paper/40"}`}
            style={{ transform: `scaleX(${Math.min(1, t.points / toWin)})`, ...(t.color ? { backgroundColor: t.color, opacity: isLead ? 1 : 0.7 } : {}) }} />
        </div>
      </div>
    );
  };
  return (
    <section className="rounded-2xl bg-brand px-4 py-6 text-paper" aria-label="Standings">
      <div className="flex items-start">
        {side(a)}
        <div className="mx-2 mt-8 h-16 w-px shrink-0 bg-paper/15" aria-hidden />
        {side(b)}
      </div>
      <p className="mt-6 text-center text-sm text-paper/70">
        {complete && lead ? `${lead.name} wins` : lead ? `${lead.name} leads by ${fmt(diff)}` : "All square"}
        <span className="mx-2 text-paper/30" aria-hidden>·</span>
        <span className="tnum">{fmt(toWin)}</span> to win
      </p>
    </section>
  );
}
