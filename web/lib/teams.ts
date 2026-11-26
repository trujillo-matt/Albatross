// Team colour and tee-time helpers shared by the admin site and the player pages.
// The same default colours are used on iOS (Color.teamDefaultA / teamDefaultB), so a team with no colour set looks the same everywhere.
import type { TTeam, TTeeTime, TPlayer } from "./types";

export const DEFAULT_TEAM_COLORS = { A: "#006747", B: "#731F24" } as const;

/** Colours offered when setting a team's colour. The admin can also pick any colour. */
export const TEAM_COLOR_PRESETS = ["#006747", "#731F24", "#1D4E89", "#B8860B", "#5B2A86", "#C2410C", "#0F766E", "#111827"] as const;

export function teamColor(team: Pick<TTeam, "color" | "side"> | undefined, fallbackSide: "A" | "B" = "A"): string {
  return team?.color || DEFAULT_TEAM_COLORS[team?.side ?? fallbackSide];
}

/** Black or white text, whichever reads better on the colour. */
export function textOn(hex: string): "#FFFFFF" | "#111111" {
  const n = parseInt(hex.replace("#", ""), 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => { const c = v / 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.4 ? "#111111" : "#FFFFFF";
}

/** A tee time as the viewer would read it: "Sat, 8:10 AM". */
export function teeTimeLabel(iso: string): string {
  return new Date(iso).toLocaleString(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" });
}

/** The value a datetime-local input wants, in the viewer's own time zone. */
export function toLocalInput(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** Back from a datetime-local value to an ISO instant, or null when the field is empty. */
export function fromLocalInput(value: string): string | null {
  return value ? new Date(value).toISOString() : null;
}

/**
 * Fills tee times in order: players are taken `perGroup` at a time, each group `gapMinutes` after the one before.
 * Returns a local-input value per user id. Pure, so it can be tested.
 */
export function fillTeeTimes(userIds: string[], firstLocal: string, gapMinutes: number, perGroup: number): Record<string, string> {
  const out: Record<string, string> = {};
  if (!firstLocal || perGroup < 1) return out;
  const start = new Date(firstLocal).getTime();
  userIds.forEach((id, i) => { out[id] = toLocalInput(new Date(start + Math.floor(i / perGroup) * gapMinutes * 60000).toISOString()); });
  return out;
}

/** Tee times for `count` groups: the first at `firstLocal`, each `gapMinutes` after the one before (local-input values). */
export function groupTimes(firstLocal: string, gapMinutes: number, count: number): string[] {
  if (!firstLocal || count < 1) return [];
  const start = new Date(firstLocal).getTime();
  return Array.from({ length: count }, (_, i) => toLocalInput(new Date(start + i * gapMinutes * 60000).toISOString()));
}

/**
 * Moves players onto a new set of group times without losing their groups: whoever was in the nth old group goes to the
 * nth new one, and anyone whose group no longer exists is left without a time.
 */
export function moveToNewTimes(values: Record<string, string>, oldTimes: string[], newTimes: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [uid, time] of Object.entries(values)) {
    const at = oldTimes.indexOf(time);
    out[uid] = time && at >= 0 ? newTimes[at] ?? "" : "";
  }
  return out;
}

/** A player's tee time for a session, if one is set. */
export function teeTimeFor(teeTimes: TTeeTime[], sessionId: string, userId: string): string | null {
  return teeTimes.find((t) => t.session_id === sessionId && t.user_id === userId)?.tee_time ?? null;
}

/** Accepted players grouped by tee time for one session, earliest first. */
export function groupsForSession(teeTimes: TTeeTime[], sessionId: string, players: TPlayer[]): { time: string; players: TPlayer[] }[] {
  const byTime = new Map<string, TPlayer[]>();
  for (const t of teeTimes.filter((x) => x.session_id === sessionId)) {
    const p = players.find((q) => q.user_id === t.user_id);
    if (p) byTime.set(t.tee_time, [...(byTime.get(t.tee_time) ?? []), p]);
  }
  return [...byTime.entries()].sort((a, b) => new Date(a[0]).getTime() - new Date(b[0]).getTime()).map(([time, ps]) => ({ time, players: ps }));
}
