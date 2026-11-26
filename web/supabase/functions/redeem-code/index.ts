// POST { code } -> { access_token, refresh_token, tournament_id }
// Turns a player code into a normal Supabase session for the pre-created managed player account.
import { createClient } from "npm:@supabase/supabase-js@2";
import { cors, hashCode, json, randomPassword, sha256Hex } from "../_shared.ts";

// Failed attempts allowed per IP within the window. A group on one connection (a clubhouse, a hotel) shares an IP, so this has to
// leave room for everyone mistyping a code a few times. It stays far too small to guess one: codes are 8 characters from 32
// symbols (about 1.1e12), so 60 guesses per 10 minutes is a few thousand a day from one address.
const MAX_FAILS = 60;
const WINDOW_MINUTES = 10;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
  const ipHash = await sha256Hex(`${Deno.env.get("CODE_PEPPER") ?? ""}:ip:${ip}`);

  const since = new Date(Date.now() - WINDOW_MINUTES * 60_000).toISOString();
  const { count } = await admin.from("code_redeem_attempts").select("id", { count: "exact", head: true })
    .eq("ip_hash", ipHash).eq("success", false).gte("created_at", since);
  if ((count ?? 0) >= MAX_FAILS) return json({ error: "Too many attempts. Try again in a few minutes." }, 429);

  const fail = async (message: string, status = 401) => {
    await admin.from("code_redeem_attempts").insert({ ip_hash: ipHash, success: false });
    return json({ error: message }, status);
  };

  let body: { code?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid request" }, 400); }
  const code = String(body.code ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (code.length !== 8) return fail("That code is not valid.");

  const { data: row } = await admin.from("player_access_codes")
    .select("id, user_id, tournament_id, status, expires_at").eq("code_hash", await hashCode(code)).maybeSingle();
  if (!row || row.status !== "active") return fail("That code is not valid.");
  if (row.expires_at && new Date(row.expires_at) < new Date()) return fail("That code has expired. Ask the admin for a new one.");

  const { data: t } = await admin.from("tournaments").select("status").eq("id", row.tournament_id).single();
  if (t?.status === "complete") return fail("This tournament is finished.", 403);

  const { data: u, error: uErr } = await admin.auth.admin.getUserById(row.user_id);
  if (uErr || !u.user?.email) return json({ error: "Player account is unavailable." }, 500);

  // Mint a session: rotate the managed user's random password, then sign in with it server side.
  const password = randomPassword();
  const upd = await admin.auth.admin.updateUserById(row.user_id, { password });
  if (upd.error) return json({ error: "Could not start a session." }, 500);
  const { data: s, error: sErr } = await anon.auth.signInWithPassword({ email: u.user.email, password });
  if (sErr || !s.session) return json({ error: "Could not start a session." }, 500);

  await admin.from("player_access_codes").update({ last_used_at: new Date().toISOString() }).eq("id", row.id);
  await admin.from("code_redeem_attempts").insert({ ip_hash: ipHash, success: true });

  return json({
    access_token: s.session.access_token,
    refresh_token: s.session.refresh_token,
    tournament_id: row.tournament_id,
  });
});
