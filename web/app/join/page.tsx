"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { functionsUrl, supabase } from "@/lib/supabase";
import { normalizeCode } from "@/lib/code";
import Page from "@/components/Page";

export default function Join() {
  const router = useRouter();
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true); setErr(null);
    try {
      const res = await fetch(`${functionsUrl}/redeem-code`, {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "" },
        body: JSON.stringify({ code: normalizeCode(code) }),
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body.error ?? "Code not accepted");
      const { error } = await supabase.auth.setSession({
        access_token: body.access_token, refresh_token: body.refresh_token,
      });
      if (error) throw error;
      router.replace(`/t/${body.tournament_id}`);
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Something went wrong");
    }
    setBusy(false);
  };

  return (
    <Page>
      <form onSubmit={submit} className="space-y-7 pt-12">
        <div className="space-y-2">
          <h1 className="h1">Enter your player code</h1>
          <p className="muted">Your admin gave you an 8 character code, like K7M2-9QXH</p>
        </div>
        <input className="input text-center font-mono text-2xl tracking-widest" autoFocus autoCapitalize="characters" autoCorrect="off"
          aria-label="Player code" placeholder="XXXX-XXXX" value={code} onChange={(e) => setCode(e.target.value)} />
        <button className="btn w-full" disabled={busy || normalizeCode(code).length < 8}>{busy ? "Checking" : "Continue"}</button>
        {err && <p role="alert" className="text-sm text-bad">{err}</p>}
      </form>
    </Page>
  );
}
