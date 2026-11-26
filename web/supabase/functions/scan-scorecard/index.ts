// POST { images: [base64 JPEG, ...] } with the user's normal session token -> { text }
// Reads 1 or 2 scorecard photos with Gemini. The Gemini key lives only here, as the
// GEMINI_API_KEY function secret; the iOS app never sees it.
import { createClient } from "npm:@supabase/supabase-js@2";
import { cors, json } from "../_shared.ts";

const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
const MAX_IMAGES = 2;
const MAX_IMAGE_BASE64_CHARS = 3_000_000; // about 2.2 MB of JPEG per image

const PROMPT = `You are analyzing a photo (or photos) of a physical paper golf scorecard. \
There may be 1 image (all 18 holes on one card) or 2 images (front 9 on one \
side, back 9 on the other). Scores are typically handwritten in pencil.

Extract the following and return ONLY valid JSON — no markdown, no explanation:

{
  "courseName": "string or null",
  "pars": [18 integers, each 3–5] or null,
  "players": [
    { "name": "string", "scores": [18 values — integer 1–15 or null if illegible] }
  ]
}

Rules:
- The HOLE row (1,2,3…18) and HANDICAP/INDEX row are NOT scores — skip them.
- The PAR row contains values like 3,4,5 — read those values into the "pars" array.
- "OUT" = front-9 total, "IN" = back-9 total, "TOT" = grand total — skip these columns.
- If a player name is unclear, use "Player 1", "Player 2", etc.
- If you are not fully confident about a score value, use null — do not guess.
- Players whose scores are entirely null should be omitted.
- Return ONLY the JSON object, starting with { and ending with }.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // Only signed-in users can spend the Gemini quota.
  const caller = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
  const { data: who } = await caller.auth.getUser();
  if (!who.user) return json({ error: "Sign in to scan a scorecard." }, 401);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "Scanning is not configured." }, 500);

  let body: { images?: unknown };
  try { body = await req.json(); } catch { return json({ error: "Invalid request" }, 400); }
  const images = Array.isArray(body.images) ? body.images : [];
  if (images.length < 1 || images.length > MAX_IMAGES) return json({ error: "Send 1 or 2 images." }, 400);
  if (!images.every((i) => typeof i === "string" && i.length > 0 && i.length <= MAX_IMAGE_BASE64_CHARS)) {
    return json({ error: "An image is empty or too large." }, 413);
  }

  const parts = [
    ...images.map((data) => ({ inline_data: { mime_type: "image/jpeg", data } })),
    { text: PROMPT },
  ];

  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
    body: JSON.stringify({
      contents: [{ parts }],
      generationConfig: { temperature: 0, maxOutputTokens: 2048 },
    }),
  });

  if (!res.ok) {
    console.error("Gemini error", res.status, await res.text());
    const status = res.status === 429 ? 429 : 502;
    return json({ error: status === 429 ? "Scanner is busy. Try again in a minute." : "Scanner failed." }, status);
  }

  const out = await res.json();
  const text = out?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string") {
    console.error("Unexpected Gemini response", JSON.stringify(out).slice(0, 2000));
    return json({ error: "Scanner returned an unexpected response." }, 502);
  }
  return json({ text });
});
