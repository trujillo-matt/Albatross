// Port of calculateMatchPlayPoints / BestBall / StrokePlay in Albatross/Models/Tournament.swift.
// The database function compute_matchup_result is the source of truth for stored results;
// this copy powers live "match status" on the client and must stay in parity (see scoring.test.ts).
import type { MatchType } from "./types";

type Scores = (number | null)[];
export interface Points { a: number; b: number }

const minAt = (rounds: Scores[], hole: number): number | null => {
  const vals = rounds.map((r) => r[hole]).filter((v): v is number => typeof v === "number");
  return vals.length ? Math.min(...vals) : null;
};
const total = (r: Scores) => r.reduce<number>((s, v) => s + (v ?? 0), 0);

export function matchPlayPoints(a: Scores[], b: Scores[]): Points {
  let aH = 0, bH = 0;
  for (let h = 0; h < 18; h++) {
    const x = minAt(a, h), y = minAt(b, h);
    if (x === null || y === null) continue;
    if (x < y) aH += 1; else if (y < x) bH += 1; else { aH += 0.5; bH += 0.5; }
  }
  if (aH > bH) return { a: 1, b: 0 };
  if (bH > aH) return { a: 0, b: 1 };
  return { a: 0.5, b: 0.5 };
}

export function bestBallPoints(a: Scores[], b: Scores[]): Points {
  const sum = (rs: Scores[]) => {
    let t = 0;
    for (let h = 0; h < 18; h++) { const m = minAt(rs, h); if (m !== null) t += m; }
    return t;
  };
  const x = sum(a), y = sum(b);
  if (x < y) return { a: 1, b: 0 };
  if (y < x) return { a: 0, b: 1 };
  return { a: 0.5, b: 0.5 };
}

export function strokePlayPoints(a: Scores[], b: Scores[]): Points {
  const lo = (rs: Scores[]) => (rs.length ? Math.min(...rs.map(total)) : Number.MAX_SAFE_INTEGER);
  const x = lo(a), y = lo(b);
  if (x < y) return { a: 1, b: 0 };
  if (y < x) return { a: 0, b: 1 };
  return { a: 0.5, b: 0.5 };
}

export function matchPoints(type: MatchType, a: Scores[], b: Scores[]): Points {
  if (type === "match_play") return matchPlayPoints(a, b);
  if (type === "stroke_play") return strokePlayPoints(a, b);
  return bestBallPoints(a, b);
}

/** Dormie: one side is up by as many holes as are left, so it cannot lose the match. */
export const isDormie = (up: number, thru: number): boolean => up !== 0 && thru < 18 && Math.abs(up) === 18 - thru;

/** Holes up/down for match play status, from side A's view, over holes both sides have scored. */
export function matchPlayStatus(a: Scores[], b: Scores[]): { up: number; thru: number } {
  let up = 0, thru = 0;
  for (let h = 0; h < 18; h++) {
    const x = minAt(a, h), y = minAt(b, h);
    if (x === null || y === null) continue;
    thru += 1;
    if (x < y) up += 1; else if (y < x) up -= 1;
  }
  return { up, thru };
}
