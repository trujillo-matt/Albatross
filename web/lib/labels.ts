import type { MatchType, MatchupStatus, SessionStatus, TournamentStatus } from "./types";

export const TOURNAMENT_STATUS: Record<TournamentStatus, string> = {
  setup: "Setup", draft: "Draft", active: "In progress", complete: "Complete",
};
export const MATCHUP_STATUS: Record<MatchupStatus, string> = {
  pending: "Pending", active: "In progress", complete: "Complete",
};
export const FORMAT: Record<MatchType, string> = {
  scramble: "Scramble", best_ball: "Best ball", match_play: "Match play", stroke_play: "Stroke play", alternate_shot: "Alternate shot",
};
export const SESSION_STATUS: Record<SessionStatus, string> = {
  pending: "Up next", lineup: "Lineup", callouts: "Callouts", locked: "Locked in", complete: "Complete",
};

/** "Nov 20, 6:03 PM" in the viewer's locale and time zone. */
export function shortDateTime(iso: string): string {
  return new Date(iso).toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

/** "2 minutes ago", "3 hours ago", "yesterday". Past a week it falls back to the date. Matches how the iOS app words it. */
export function timeAgo(iso: string, now: number = Date.now()): string {
  const seconds = Math.round((new Date(iso).getTime() - now) / 1000);
  const abs = Math.abs(seconds);
  const rtf = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
  if (abs < 45) return "just now";
  if (abs < 3600) return rtf.format(Math.round(seconds / 60), "minute");
  if (abs < 86400) return rtf.format(Math.round(seconds / 3600), "hour");
  if (abs < 7 * 86400) return rtf.format(Math.round(seconds / 86400), "day");
  return shortDateTime(iso);
}
