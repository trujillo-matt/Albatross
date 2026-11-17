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
    <form onSubmit={go} className="space-y-3 pt-10">
      <h1 className="text-2xl font-bold text-brand">Admin sign in</h1>
      <p className="muted">Use the same email and password as the Albatross app.</p>
      <input className="input" type="email" placeholder="Email" value={email} onChange={(e) => setEmail(e.target.value)} />
      <input className="input" type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} />
      <button className="btn w-full" disabled={busy || !email || !password}>Sign in</button>
      {err && <p className="text-sm text-red-600">{err}</p>}
    </form>
  );
}
