// Group scoring: one player enters everyone's strokes. Pure helpers, mirrored by the database functions in
// docs/migrations/009_group_scoring.sql (which decide who owns which card).
import type { MatchType, TMatchup } from "./types";

export const DEFAULT_PARS = [4, 4, 3, 4, 5, 3, 4, 4, 5, 4, 3, 4, 5, 4, 3, 4, 5, 4];

/** Scramble and alternate shot play one ball per side, so the group has one card per side, not per player. */
export const isTeamCardFormat = (t: MatchType) => t === "scramble" || t === "alternate_shot";

type Sides = Pick<TMatchup, "match_type" | "team_a_player_ids" | "team_b_player_ids">;

/** Who owns each card, in display order: side A first. Matches what start_group_scoring creates. */
export function cardOwners(m: Sides): string[] {
  if (isTeamCardFormat(m.match_type)) return [m.team_a_player_ids[0], m.team_b_player_ids[0]].filter(Boolean);
  return [...m.team_a_player_ids, ...m.team_b_player_ids];
}

export const sideOf = (m: Sides, userId: string): "A" | "B" => (m.team_a_player_ids.includes(userId) ? "A" : "B");

/** Orders fetched cards to match cardOwners, dropping any card that is not part of the group. */
export function orderCards<T extends { user_id: string }>(m: Sides, cards: T[]): T[] {
  return cardOwners(m).map((o) => cards.find((c) => c.user_id === o)).filter((c): c is T => !!c);
}

export function groupHasAllCards(m: Sides, cards: { user_id: string }[]): boolean {
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

export const groupFilled = (cards: { scores: (number | null)[] }[]) => cards.reduce((s, c) => s + c.scores.filter((v) => v !== null).length, 0);
export const groupComplete = (cards: { scores: (number | null)[] }[]) => cards.length > 0 && groupFilled(cards) === 18 * cards.length;
export const cardTotal = (scores: (number | null)[]) => scores.reduce<number>((s, v) => s + (v ?? 0), 0);
