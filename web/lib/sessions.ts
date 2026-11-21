import type { MatchType, SessionStatus, TMatchup, TPlayer, TSession, TTeam, TournamentData } from "./types";
import { orderedTeams } from "./draft.ts";

/** Players on each side of one match: singles formats 1, pairs formats 2. Mirrors players_per_side() in migration 008. */
export function playersPerSide(type: MatchType): number {
  return type === "match_play" || type === "stroke_play" ? 1 : 2;
}

/** Matches a session makes from the rosters: floor(smaller team / players per side). Extras sit out. */
export function sessionMatchCount(teamA: number, teamB: number, type: MatchType): number {
  return Math.floor(Math.min(teamA, teamB) / playersPerSide(type));
}

/** Points on offer for a plan of sessions and the total needed to win (more than half). */
export function planTotals(sessions: { match_type: MatchType }[], teamA: number, teamB: number) {
  const matches = sessions.reduce((n, s) => n + sessionMatchCount(teamA, teamB, s.match_type), 0);
  return { matches, pointsToWin: Math.floor(matches / 2) + 0.5 };
}

export interface DayGroup { day: number; sessions: SessionView[] }
export interface SessionView { session: TSession; matchups: TMatchup[] }

/** Sessions grouped by day in play order, each with its matches in match order. */
export function groupByDay(sessions: TSession[], matchups: TMatchup[]): DayGroup[] {
  const days = new Map<number, SessionView[]>();
  const sorted = [...sessions].sort((a, b) => a.day_number - b.day_number || a.session_number - b.session_number);
  for (const session of sorted) {
    const ms = matchups.filter((m) => m.session_id === session.id).sort((a, b) => a.matchup_number - b.matchup_number);
    days.set(session.day_number, [...(days.get(session.day_number) ?? []), { session, matchups: ms }]);
  }
  return [...days.entries()].map(([day, s]) => ({ day, sessions: s }));
}

export function sessionPoints(matchups: TMatchup[]): { a: number; b: number } {
  return matchups.reduce((t, m) => ({ a: t.a + Number(m.points_team_a || 0), b: t.b + Number(m.points_team_b || 0) }), { a: 0, b: 0 });
}

/** The session being played: the first that is not complete. */
export function currentSession(sessions: TSession[]): TSession | null {
  const sorted = [...sessions].sort((a, b) => a.day_number - b.day_number || a.session_number - b.session_number);
  return sorted.find((s) => s.status !== "complete") ?? sorted[sorted.length - 1] ?? null;
}

export function isLocked(m: TMatchup): boolean { return !!m.called_at; }

/** Who sits out of a session: accepted players on the team who are in none of its matches. */
export function sitOuts(team: TTeam, players: TPlayer[], matchups: TMatchup[], side: "A" | "B"): TPlayer[] {
  const playing = new Set(matchups.flatMap((m) => (side === "A" ? m.team_a_player_ids : m.team_b_player_ids)));
  return players.filter((p) => p.team_id === team.id && p.invite_status === "accepted" && !playing.has(p.user_id));
}

export interface CalloutState {
  status: SessionStatus;
  /** Team whose captain acts now, or null outside callouts. */
  turnTeamId: string | null;
  openMatches: number;
  lockedMatches: number;
  /** True when a pass by the person on turn would lock everything (one pass already made). */
  nextPassLocks: boolean;
}

export function calloutState(session: TSession, matchups: TMatchup[]): CalloutState {
  const locked = matchups.filter(isLocked).length;
  return {
    status: session.status,
    turnTeamId: session.status === "callouts" ? session.turn_team_id : null,
    openMatches: matchups.length - locked,
    lockedMatches: locked,
    nextPassLocks: session.status === "callouts" && session.consecutive_passes >= 1,
  };
}

/** Which side (A or B) a team is, using the same canonical order as the database. */
export function sideOf(teams: TTeam[], teamId: string | null | undefined): "A" | "B" | null {
  const [a, b] = orderedTeams(teams);
  if (a && teamId === a.id) return "A";
  if (b && teamId === b.id) return "B";
  return null;
}

/** The unit (one player or a pair) a side fields in a match. */
export function unitOf(m: TMatchup, side: "A" | "B"): string[] {
  return side === "A" ? m.team_a_player_ids : m.team_b_player_ids;
}

export function sameUnit(x: string[], y: string[]): boolean {
  return x.length === y.length && x.every((id) => y.includes(id));
}

/** A day plan as the create form edits it. */
export interface PlanSession { label: string; match_type: MatchType }
export interface PlanDay { course: string; sessions: PlanSession[] }

export const PRESETS: { id: string; name: string; days: PlanSession[] }[] = [
  { id: "ryder", name: "Ryder Cup day", days: [{ label: "AM", match_type: "alternate_shot" }, { label: "PM", match_type: "best_ball" }] },
  { id: "singles", name: "Singles day", days: [{ label: "Singles", match_type: "match_play" }] },
  { id: "invitational", name: "Invitational day", days: [{ label: "AM", match_type: "scramble" }, { label: "PM", match_type: "alternate_shot" }] },
];

/** Rows to insert into tournament_sessions for a plan. Match counts are filled in by start_tournament. */
export function planToSessionRows(tournamentId: string, plan: PlanDay[]) {
  return plan.flatMap((d, di) => d.sessions.map((s, si) => ({
    tournament_id: tournamentId, day_number: di + 1, session_number: si + 1, label: s.label.trim() || null,
    match_type: s.match_type, course_name: d.course.trim() || null,
  })));
}

/** Course for a match: its session's course, else that day's course row, else the old "round number = match number" row. */
export function courseForMatch(data: Pick<TournamentData, "sessions" | "courses">, m: Pick<TMatchup, "session_id" | "matchup_number">): { name: string | undefined; id: string | null | undefined } {
  const s = data.sessions.find((x) => x.id === m.session_id);
  if (s) {
    const day = data.courses.find((c) => c.round_number === s.day_number);
    return { name: s.course_name || day?.course_name || undefined, id: s.course_id ?? day?.course_id };
  }
  const c = data.courses.find((x) => x.round_number === m.matchup_number);
  return { name: c?.course_name, id: c?.course_id };
}
