// Called by the push_queue trigger (docs/migrations/023) and safe to call at any time: it sends what is waiting.
// Each row is claimed by claim_push_queue before it is sent, so a row goes out once however often this runs.
// Secrets: APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID, and optionally APNS_BUNDLE_ID.
import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared.ts";
import { apnsConfig, providerToken, sendAlert, sendLiveActivity } from "../_apns.ts";

interface QueueRow { id: string; user_id: string; kind: string; title: string; body: string; data: Record<string, unknown>; time_sensitive: boolean }

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  // Not set up yet: leave the rows waiting.
  const config = apnsConfig();
  if (!config) return json({ skipped: "APNs is not configured" });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: claimed, error } = await db.rpc("claim_push_queue", { p_limit: 50 });
  if (error) return json({ error: error.message }, 500);
  const rows = (claimed ?? []) as QueueRow[];
  const jwt = await providerToken(config.keyP8, config.keyId, config.teamId);
  const live = await updateLiveActivities(db, jwt, config.bundleId);
  if (rows.length === 0) return json({ sent: 0, live });

  const { data: tokens } = await db.from("device_tokens").select("token, user_id").eq("enabled", true).in("user_id", [...new Set(rows.map((r) => r.user_id))]);
  const tokensByUser = new Map<string, string[]>();
  for (const t of (tokens ?? []) as { token: string; user_id: string }[]) tokensByUser.set(t.user_id, [...(tokensByUser.get(t.user_id) ?? []), t.token]);

  let sent = 0;
  const gone: string[] = [];
  for (const row of rows) {
    const data: Record<string, string> = { queue_id: row.id, kind: row.kind };
    for (const [key, value] of Object.entries(row.data ?? {})) data[key] = String(value);
    for (const token of tokensByUser.get(row.user_id) ?? []) {
      const result = await sendAlert(token, jwt, config.bundleId, { title: row.title, body: row.body }, data, row.id, { timeSensitive: row.time_sensitive });
      if (result.ok) sent += 1; else if (result.gone) gone.push(token);
      else console.error("push failed", result.status, result.reason);
    }
  }
  if (gone.length) await db.from("device_tokens").delete().in("token", gone);
  return json({ claimed: rows.length, sent, removed: gone.length, live });
});

/** One push per followed match whose score changed, carrying the standing as it is now. */
// deno-lint-ignore no-explicit-any
async function updateLiveActivities(db: any, jwt: string, bundleId: string): Promise<number> {
  const { data: claimed } = await db.rpc("claim_live_activity_matchups", { p_limit: 100 });
  const matchups = ((claimed ?? []) as { matchup_id: string }[]).map((r) => r.matchup_id);
  let sent = 0;
  for (const matchupId of matchups) {
    const [{ data: status }, { data: tokens }] = await Promise.all([
      db.rpc("match_live_status", { p_matchup: matchupId }),
      db.from("live_activity_tokens").select("token").eq("matchup_id", matchupId),
    ]);
    const standing = (status as { lead: number; thru: number; finished: boolean }[] | null)?.[0];
    if (!standing || !tokens?.length) continue;
    const state = { holesPlayed: standing.thru, lead: standing.lead, finished: standing.finished };
    const gone: string[] = [];
    for (const { token } of tokens as { token: string }[]) {
      const result = await sendLiveActivity(token, jwt, bundleId, state, standing.finished ? "end" : "update");
      if (result.ok) sent += 1; else if (result.gone) gone.push(token);
      else console.error("live activity push failed", result.status, result.reason);
    }
    if (gone.length) await db.from("live_activity_tokens").delete().in("token", gone);
  }
  return sent;
}
