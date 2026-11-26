// Offline-tolerant hole score writes. Each write is queued in localStorage and flushed in order,
// so a dropped connection on the course never loses a score. Last write per (round, hole) wins.
import { supabase } from "./supabase.ts";

export interface PendingScore { roundId: string; hole: number; strokes: number | null }
const KEY = "albatross-score-queue";

function read(): PendingScore[] {
  try { return JSON.parse(localStorage.getItem(KEY) ?? "[]"); } catch { return []; }
}
function write(q: PendingScore[]) {
  try { localStorage.setItem(KEY, JSON.stringify(q)); } catch { /* storage unavailable */ }
}

/** The scores still waiting to be sent, oldest first. */
export function pendingScores(): PendingScore[] {
  return read();
}

export function pendingCount(roundId?: string): number {
  return read().filter((p) => !roundId || p.roundId === roundId).length;
}

export function enqueue(item: PendingScore) {
  const q = read().filter((p) => !(p.roundId === item.roundId && p.hole === item.hole));
  q.push(item);
  write(q);
}

/** What the server says back for one write. */
export interface SendError { message: string; code?: string }
export type Send = (item: PendingScore) => Promise<{ error: SendError | null }>;

const sendToServer: Send = async (item) => {
  const { error } = await supabase.rpc("set_hole_score", { p_round: item.roundId, p_hole: item.hole, p_strokes: item.strokes });
  return { error };
};

/**
 * The server clearly refused this score and will refuse it again: not your card, a bad hole or stroke count,
 * or someone else is keeping score for the group. Only these are dropped. Anything else (no signal, an expired
 * sign-in, a server error, a message we do not recognise) keeps the score queued to be retried.
 */
export function isServerRejection(error: SendError): boolean {
  return error.code === "P0001"
    && /round not found|not yours|already completed|hole must be|strokes must be|scorer is keeping score/i.test(error.message);
}

let flushing = false;
/**
 * Sends queued scores in order. Drops only the ones the server clearly rejects (see isServerRejection).
 * On any other failure it stops, leaves the rest queued, and reports why in `stalled`, so the next flush retries in order.
 */
export async function flush(send: Send = sendToServer): Promise<{ sent: number; rejected: string[]; stalled: string | null }> {
  if (flushing) return { sent: 0, rejected: [], stalled: null };
  flushing = true;
  let sent = 0; let stalled: string | null = null; const rejected: string[] = [];
  try {
    let q = read();
    while (q.length) {
      const item = q[0];
      const { error } = await send(item);
      if (error) {
        if (!isServerRejection(error)) { stalled = error.message; break; }
        rejected.push(`Hole ${item.hole}: ${error.message}`);
      } else sent += 1;
      q = q.slice(1);
      write(q);
    }
  } catch (e) {
    stalled = e instanceof Error ? e.message : "Could not reach the server";   // offline: the queue stays intact
  } finally {
    flushing = false;
  }
  return { sent, rejected, stalled };
}
