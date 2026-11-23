"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase";

export default function AdminSignIn() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const go = async (e: React.FormEvent) => {
    e.preventDefault(); setBusy(true); setErr(null);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) setErr(error.message);
    setBusy(false);
  };
  return (
    <form onSubmit={go} className="space-y-7 pt-12">
      <div className="space-y-2">
        <h1 className="h1">Admin sign in</h1>
        <p className="muted">Use the email and password from the Albatross app</p>
      </div>
      <div className="space-y-3">
        <input className="input" type="email" autoComplete="email" aria-label="Email" placeholder="Email" value={email} onChange={(e) => setEmail(e.target.value)} />
        <input className="input" type="password" autoComplete="current-password" aria-label="Password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} />
      </div>
      <button className="btn w-full" disabled={busy || !email || !password}>Sign in</button>
      {err && <p role="alert" className="text-sm text-bad">{err}</p>}
    </form>
  );
}
