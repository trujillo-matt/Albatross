// Offline-tolerant hole score writes. Each write is queued in localStorage and flushed in order,
// so a dropped connection on the course never loses a score. Last write per (round, hole) wins.
import { supabase } from "./supabase";

export interface PendingScore { roundId: string; hole: number; strokes: number | null }
const KEY = "albatross-score-queue";

function read(): PendingScore[] {
  try { return JSON.parse(localStorage.getItem(KEY) ?? "[]"); } catch { return []; }
}
function write(q: PendingScore[]) {
  try { localStorage.setItem(KEY, JSON.stringify(q)); } catch { /* storage unavailable */ }
}

export function pendingCount(roundId?: string): number {
  return read().filter((p) => !roundId || p.roundId === roundId).length;
}

export function enqueue(item: PendingScore) {
  const q = read().filter((p) => !(p.roundId === item.roundId && p.hole === item.hole));
  q.push(item);
  write(q);
}

let flushing = false;
/** Sends queued scores in order. Stops at the first network failure; drops items the server rejects. */
export async function flush(): Promise<{ sent: number; rejected: string[] }> {
  if (flushing) return { sent: 0, rejected: [] };
  flushing = true;
  let sent = 0; const rejected: string[] = [];
  try {
    let q = read();
    while (q.length) {
      const item = q[0];
      const { error } = await supabase.rpc("set_hole_score", {
        p_round: item.roundId, p_hole: item.hole, p_strokes: item.strokes,
      });
      if (error) {
        const network = /fetch|network|failed to fetch|timeout/i.test(error.message);
        if (network) break;
        rejected.push(`Hole ${item.hole}: ${error.message}`);
      } else sent += 1;
      q = q.slice(1);
      write(q);
    }
  } catch { /* offline: leave queue intact */ }
  flushing = false;
  return { sent, rejected };
}
