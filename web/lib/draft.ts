import type { TPlayer, TTeam } from "./types";

/** Snake order for 2 teams: A, B, B, A, A, B, B, A ... */
export function snakeIsTeamATurn(pickNumber: number): boolean {
  const pos = pickNumber % 4;
  return pos === 0 || pos === 3;
}

/** Picks made so far. Captains are pre-placed on their teams and do not count. */
export function draftPickCount(players: TPlayer[], teams: TTeam[]): number {
  const captains = new Set(teams.map((t) => t.captain_user_id).filter(Boolean));
  return players.filter((p) => p.team_id && !captains.has(p.user_id)).length;
}

/** Teams in canonical order: side A first, B second (never rely on row order). */
export function orderedTeams(teams: TTeam[]): TTeam[] {
  return [...teams].sort((a, b) => (a.side ?? a.name).localeCompare(b.side ?? b.name) || a.id.localeCompare(b.id));
}

export function defaultPointsToWin(totalMatches: number): number {
  return totalMatches / 2 + 0.5;
}
