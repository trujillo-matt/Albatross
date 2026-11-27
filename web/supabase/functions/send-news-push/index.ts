// Called by the news_push trigger (docs/migrations/022) with { id } for a new tournament_news row.
// Sends an APNs alert to every accepted player of that tournament who has a registered phone.
// Secrets: APNS_KEY_P8 (the .p8 file's text), APNS_KEY_ID, APNS_TEAM_ID, and optionally APNS_BUNDLE_ID (default TrujSoft.Albatross).
// Safe to call twice for the same row: the row is claimed first, and only the first call sends.
import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared.ts";
import { providerToken, sendAlert } from "./apns.ts";
import { type Lookup, type Matchup, type NewsRow, writeStory } from "./story.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let id: unknown;
  try { ({ id } = await req.json()); } catch { return json({ error: "Invalid request" }, 400); }
  if (typeof id !== "string" || !UUID.test(id)) return json({ error: "id required" }, 400);

  const keyP8 = Deno.env.get("APNS_KEY_P8"), keyId = Deno.env.get("APNS_KEY_ID"), teamId = Deno.env.get("APNS_TEAM_ID");
  // Not set up yet: leave the row unclaimed and say why.
  if (!keyP8 || !keyId || !teamId) return json({ skipped: "APNs is not configured" });
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "TrujSoft.Albatross";

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  const { data: claimed, error: claimError } = await db.from("tournament_news")
    .update({ pushed_at: new Date().toISOString() }).eq("id", id).is("pushed_at", null).select().maybeSingle();
  if (claimError) return json({ error: claimError.message }, 500);
  if (!claimed) return json({ skipped: "already sent or not found" });
  const row = claimed as NewsRow;

  const [{ data: tournament }, { data: players }, { data: teams }, matchupResult] = await Promise.all([
    db.from("tournaments").select("name").eq("id", row.tournament_id).single(),
    db.from("tournament_players").select("user_id, team_id").eq("tournament_id", row.tournament_id).eq("invite_status", "accepted"),
    db.from("tournament_teams").select("id, name").eq("tournament_id", row.tournament_id),
    row.matchup_id
      ? db.from("tournament_matchups").select("matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, result").eq("id", row.matchup_id).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);
  const members = (players ?? []) as { user_id: string; team_id: string | null }[];
  if (members.length === 0) return json({ sent: 0 });

  const teamNames = Object.fromEntries(((teams ?? []) as { id: string; name: string }[]).map((t) => [t.id, t.name]));
  const matchup = (matchupResult.data ?? null) as Matchup | null;
  const { data: profiles } = await db.from("profiles").select("id, display_name").in("id", members.map((p) => p.user_id));
  const names = Object.fromEntries(((profiles ?? []) as { id: string; display_name: string }[]).map((p) => [p.id, p.display_name || "A player"]));
  const teamOf = Object.fromEntries(members.filter((p) => p.team_id && teamNames[p.team_id]).map((p) => [p.user_id, teamNames[p.team_id!]]));
  const look: Lookup = { tournamentName: tournament?.name ?? "tournament", matchup, names, teamOf, teamNames };
  const story = writeStory(row, look);

  const { data: tokens } = await db.from("device_tokens").select("token").eq("enabled", true).in("user_id", members.map((p) => p.user_id));
  const jwt = await providerToken(keyP8, keyId, teamId);
  let sent = 0;
  const gone: string[] = [];
  for (const { token } of (tokens ?? []) as { token: string }[]) {
    const result = await sendAlert(token, jwt, bundleId, story, { news_id: row.id, tournament_id: row.tournament_id }, row.id);
    if (result.ok) sent += 1; else if (result.gone) gone.push(token);
    else console.error("push failed", result.status, result.reason);
  }
  // Phones that no longer exist are forgotten.
  if (gone.length) await db.from("device_tokens").delete().in("token", gone);
  return json({ sent, removed: gone.length });
});
