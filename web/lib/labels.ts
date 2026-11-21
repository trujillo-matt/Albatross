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
