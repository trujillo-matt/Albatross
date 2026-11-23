import type { TournamentStatus, MatchupStatus } from "@/lib/types";
import { MATCHUP_STATUS, TOURNAMENT_STATUS } from "@/lib/labels";

export type Tone = "live" | "warn" | "idle";
const DOT: Record<Tone, string> = { live: "bg-brand-accent", warn: "bg-warn", idle: "bg-stone-300" };

/** The status dot: green is live or synced, amber needs attention, grey is idle. Used wherever state is shown. */
export function Dot({ tone = "idle", className = "" }: { tone?: Tone; className?: string }) {
  return <span aria-hidden className={`inline-block h-2 w-2 shrink-0 rounded-full ${DOT[tone]} ${className}`} />;
}

/** A yellow C before a captain's name. Read aloud as "Captain". */
export function CaptainBadge() {
  return (
    <span role="img" aria-label="Captain" className="mr-2 inline-flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-amber-400 align-[-1px] text-[10px] font-semibold leading-none text-stone-900">C</span>
  );
}

export function Status({ tone, children }: { tone: Tone; children: React.ReactNode }) {
  return <span className="inline-flex items-center gap-2 text-sm text-stone-600"><Dot tone={tone} />{children}</span>;
}

export function TournamentStatusLabel({ status }: { status: TournamentStatus }) {
  const tone: Tone = status === "active" ? "live" : status === "complete" ? "idle" : "warn";
  return <Status tone={tone}>{TOURNAMENT_STATUS[status]}</Status>;
}

export function MatchupStatusLabel({ status }: { status: MatchupStatus }) {
  return <Status tone={status === "active" ? "live" : "idle"}>{MATCHUP_STATUS[status]}</Status>;
}

/** Line icons, 1.5 stroke, current text color. 24px in navigation and buttons, 28px in lists. */
const base = (size: number) => ({ width: size, height: size, viewBox: "0 0 16 16", fill: "none", stroke: "currentColor", strokeWidth: 1.5, strokeLinecap: "round" as const, strokeLinejoin: "round" as const, "aria-hidden": true });
export const CheckIcon = ({ size = 24 }: { size?: number }) => <svg {...base(size)}><path d="M3 8.5 6.5 12 13 4.5" /></svg>;
export const ChevronLeftIcon = ({ size = 24 }: { size?: number }) => <svg {...base(size)}><path d="M10 3 5 8l5 5" /></svg>;

/** A small dot in a team's colour, before the team's name. */
export function TeamDot({ color }: { color: string }) {
  return <span aria-hidden className="mr-2 inline-block h-2.5 w-2.5 shrink-0 rounded-full align-[0px] ring-1 ring-black/10" style={{ backgroundColor: color }} />;
}
