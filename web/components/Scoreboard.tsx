/**
 * The standings moment: a clubhouse scoreboard. Dark brand panel, large serif tabular numerals, the leader
 * in full paper white and the other side quieter, a thin progress rule toward the points needed to win.
 */
interface Props {
  teams: [{ name: string; points: number } | undefined, { name: string; points: number } | undefined];
  toWin: number;
  complete?: boolean;
}

const fmt = (n: number) => n.toFixed(1);

export default function Scoreboard({ teams, toWin, complete = false }: Props) {
  const [a, b] = teams;
  if (!a || !b) return null;
  const lead = a.points === b.points ? null : a.points > b.points ? a : b;
  const diff = Math.abs(a.points - b.points);
  const side = (t: { name: string; points: number }) => {
    const isLead = lead === t;
    return (
      <div className="min-w-0 flex-1 text-center">
        <div className={`truncate text-sm ${isLead ? "text-paper" : "text-paper/60"}`}>{t.name}</div>
        <div className={`num text-7xl leading-none ${isLead ? "text-paper" : "text-paper/55"}`}>{fmt(t.points)}</div>
        <div className="mx-auto mt-4 h-1 w-24 overflow-hidden rounded-full bg-paper/15" role="img"
          aria-label={`${t.name}: ${fmt(t.points)} of ${fmt(toWin)} points needed`}>
          <div className={`h-full origin-left rounded-full transition-transform duration-500 ease-out ${isLead ? "bg-brand-tint" : "bg-paper/40"}`}
            style={{ transform: `scaleX(${Math.min(1, t.points / toWin)})` }} />
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
