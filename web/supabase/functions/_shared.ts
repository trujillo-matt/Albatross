// Shared helpers for the edge functions. Deploy with: supabase functions deploy redeem-code admin-players scan-scorecard
export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

// Crockford base32: no I, L, O, U. 32 symbols, so a random byte maps without modulo bias.
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
export function generateCode(length = 8): string {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (b) => ALPHABET[b % 32]).join("");
}

export async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Codes are stored as SHA-256(pepper:code). The pepper is a function secret, never in the database. */
export function hashCode(code: string): Promise<string> {
  return sha256Hex(`${Deno.env.get("CODE_PEPPER") ?? ""}:${code}`);
}

export function randomPassword(): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) => b.toString(16).padStart(2, "0")).join("");
}
