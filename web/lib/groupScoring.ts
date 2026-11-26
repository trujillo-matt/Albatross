// Group scoring: one player enters everyone's strokes. Pure helpers, mirrored by the database functions in
// docs/migrations/009_group_scoring.sql (which decide who owns which card).
import type { MatchType, TMatchup } from "./types";

export const DEFAULT_PARS = [4, 4, 3, 4, 5, 3, 4, 4, 5, 4, 3, 4, 5, 4, 3, 4, 5, 4];

/** Scramble and alternate shot play one ball per side, so the group has one card per side, not per player. */
// Shamble is not here: after the team picks a drive every player plays their own ball, so each keeps a card.
export const isTeamCardFormat = (t: MatchType) => t === "scramble" || t === "alternate_shot";

type Sides = Pick<TMatchup, "match_type" | "team_a_player_ids" | "team_b_player_ids">;
/** One match, or the matches of a foursome. */
type Group = Sides | Sides[];
const list = (g: Group): Sides[] => (Array.isArray(g) ? g : [g]);

/**
 * The matches played together as a foursome (mirrors foursome_of in migration 012). In singles formats a session's
 * matches are played two at a time, in match order: 1 and 2, 3 and 4. Any other format is one match on its own.
 */
export function foursomeOf(m: TMatchup, all: TMatchup[]): TMatchup[] {
  if (!m.session_id || (m.match_type !== "match_play" && m.match_type !== "stroke_play")) return [m];
  const inSession = all.filter((x) => x.session_id === m.session_id).sort((a, b) => a.matchup_number - b.matchup_number);
  const at = inSession.findIndex((x) => x.id === m.id);
  if (at < 0) return [m];
  const start = at - (at % 2);
  return inSession.slice(start, start + 2);
}

/** Who owns each card, in display order: side A first within each match. Matches what start_group_scoring creates. */
export function cardOwners(g: Group): string[] {
  return list(g).flatMap((m) =>
    isTeamCardFormat(m.match_type) ? [m.team_a_player_ids[0], m.team_b_player_ids[0]].filter(Boolean) : [...m.team_a_player_ids, ...m.team_b_player_ids]);
}

/** The match in the group a player belongs to. */
export function matchOf<T extends Sides>(group: T[], userId: string): T | undefined {
  return group.find((m) => m.team_a_player_ids.includes(userId) || m.team_b_player_ids.includes(userId));
}

export const sideOf = (m: Sides, userId: string): "A" | "B" => (m.team_a_player_ids.includes(userId) ? "A" : "B");

/** Orders fetched cards to match cardOwners, dropping any card that is not part of the group. */
export function orderCards<T extends { user_id: string }>(m: Group, cards: T[]): T[] {
  return cardOwners(m).map((o) => cards.find((c) => c.user_id === o)).filter((c): c is T => !!c);
}

export function groupHasAllCards(m: Group, cards: { user_id: string }[]): boolean {
  return cardOwners(m).every((o) => cards.some((c) => c.user_id === o));
}

/**
 * The next empty cell after (hole, card), walking hole by hole and, within a hole, card by card, then wrapping to the
 * start. Null when every cell is filled. `cards[i].scores[h]` is null for an empty cell.
 */
export function nextEmptyCell(cards: { scores: (number | null)[] }[], hole: number, card: number): { hole: number; card: number } | null {
  const n = cards.length;
  if (n === 0) return null;
  const total = 18 * n;
  const start = hole * n + card;
  for (let k = 1; k < total; k++) {
    const idx = (start + k) % total;
    const h = Math.floor(idx / n), c = idx % n;
    if (cards[c].scores[h] === null) return { hole: h, card: c };
  }
  return null;
}

/** Where a group's scorecards are kept on the device so a reload with no signal still shows them. */
export const cardsCacheKey = (groupKey: string) => `albatross-group-cards:${groupKey}`;

/** Lays the scores that have not reached the server yet over the cards, so nothing the scorer entered goes missing from view. */
export function applyPending<T extends { id: string; scores: (number | null)[] }>(cards: T[], pending: { roundId: string; hole: number; strokes: number | null }[]): T[] {
  if (pending.length === 0) return cards;
  return cards.map((card) => {
    const mine = pending.filter((p) => p.roundId === card.id);
    if (mine.length === 0) return card;
    const scores = [...card.scores];
    for (const p of mine) scores[p.hole - 1] = p.strokes;
    return { ...card, scores };
  });
}

export const groupFilled = (cards: { scores: (number | null)[] }[]) => cards.reduce((s, c) => s + c.scores.filter((v) => v !== null).length, 0);
export const groupComplete = (cards: { scores: (number | null)[] }[]) => cards.length > 0 && groupFilled(cards) === 18 * cards.length;
export const cardTotal = (scores: (number | null)[]) => scores.reduce<number>((s, v) => s + (v ?? 0), 0);
