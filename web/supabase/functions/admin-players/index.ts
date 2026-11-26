// POST { action, tournament_id, ... } with the admin's normal session token.
//   create_player     { display_name, team_id? }  -> { user_id, code }   (after the draft starts a team is needed; during the draft it is optional)
//   regenerate_code   { user_id }       -> { code }
//   revoke_code       { user_id }       -> { ok: true }
import { createClient } from "npm:@supabase/supabase-js@2";
import { cors, generateCode, hashCode, json, randomPassword } from "../_shared.ts";

// A code lasts about two months: long enough for a trip planned well ahead. A CODE_TTL_DAYS secret on the project overrides this.
const CODE_TTL_DAYS = Number(Deno.env.get("CODE_TTL_DAYS") ?? "60");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
  const { data: who } = await caller.auth.getUser();
  const me = who.user?.id;
  if (!me) return json({ error: "Sign in as an admin." }, 401);

  let body: { action?: string; tournament_id?: string; display_name?: string; user_id?: string; team_id?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid request" }, 400); }
  const tid = body.tournament_id;
  if (!tid) return json({ error: "tournament_id required" }, 400);

  // Admin check: creator or an is_admin player of this tournament.
  const { data: t } = await admin.from("tournaments").select("creator_user_id, status").eq("id", tid).maybeSingle();
  if (!t) return json({ error: "Tournament not found" }, 404);
  const { data: adminRow } = await admin.from("tournament_players").select("id")
    .eq("tournament_id", tid).eq("user_id", me).eq("is_admin", true).maybeSingle();
  if (t.creator_user_id !== me && !adminRow) return json({ error: "Not an admin of this tournament." }, 403);

  const issueCode = async (userId: string) => {
    await admin.from("player_access_codes").update({ status: "revoked", revoked_at: new Date().toISOString() })
      .eq("tournament_id", tid).eq("user_id", userId).eq("status", "active");
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = generateCode();
      const { error } = await admin.from("player_access_codes").insert({
        tournament_id: tid, user_id: userId, code_hash: await hashCode(code), code_hint: code.slice(-2),
        expires_at: new Date(Date.now() + CODE_TTL_DAYS * 86_400_000).toISOString(), created_by: me,
      });
      if (!error) return code;
      if (!/duplicate|unique/i.test(error.message)) throw new Error(error.message);
    }
    throw new Error("Could not generate a unique code.");
  };

  try {
    if (body.action === "create_player") {
      const name = (body.display_name ?? "").trim();
      if (!name) return json({ error: "display_name required" }, 400);
      if (t.status === "complete") return json({ error: "The tournament is finished." }, 409);

      // After the draft starts the new player joins a team (during the draft they may also join the undrafted pool).
      let teamId: string | null = null;
      if (t.status !== "setup") {
        if (body.team_id) {
          const { data: team } = await admin.from("tournament_teams").select("id").eq("id", body.team_id).eq("tournament_id", tid).maybeSingle();
          if (!team) return json({ error: "That team is not in this tournament." }, 400);
          teamId = team.id;
        } else if (t.status === "active") {
          return json({ error: "Choose a team for the new player." }, 400);
        }
      }

      const created = await admin.auth.admin.createUser({
        email: `${crypto.randomUUID()}@players.albatross.invalid`,
        password: randomPassword(), email_confirm: true,
        user_metadata: { display_name: name, managed: true },
      });
      if (created.error || !created.data.user) throw new Error(created.error?.message ?? "Could not create the player.");
      const userId = created.data.user.id;
      try {
        const p = await admin.from("profiles").upsert({ id: userId, display_name: name, is_managed: true, managed_by: me });
        if (p.error) throw new Error(p.error.message);
        const tp = await admin.from("tournament_players").insert({ tournament_id: tid, user_id: userId, invite_status: "accepted", is_admin: false, team_id: teamId });
        if (tp.error) throw new Error(tp.error.message);
        return json({ user_id: userId, code: await issueCode(userId) });
      } catch (e) {
        await admin.auth.admin.deleteUser(userId);   // roll back the half-created account
        throw e;
      }
    }

    if (body.action === "regenerate_code") {
      if (!body.user_id) return json({ error: "user_id required" }, 400);
      return json({ code: await issueCode(body.user_id) });
    }

    if (body.action === "revoke_code") {
      if (!body.user_id) return json({ error: "user_id required" }, 400);
      await admin.from("player_access_codes").update({ status: "revoked", revoked_at: new Date().toISOString() })
        .eq("tournament_id", tid).eq("user_id", body.user_id).eq("status", "active");
      return json({ ok: true });
    }
    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : "Failed" }, 500);
  }
});
