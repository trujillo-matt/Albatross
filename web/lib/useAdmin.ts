"use client";
import { useEffect, useState } from "react";
import { supabase } from "./supabase";

/** Email/password admin session (same accounts as the iOS app). */
export function useAdminSession() {
  const [user, setUser] = useState<{ id: string; email?: string } | null>(null);
  const [ready, setReady] = useState(false);
  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => { setUser(data.user ? { id: data.user.id, email: data.user.email } : null); setReady(true); });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setUser(s?.user ? { id: s.user.id, email: s.user.email } : null));
    return () => sub.subscription.unsubscribe();
  }, []);
  return { user, ready };
}

export async function callAdminFunction<T>(body: Record<string, unknown>): Promise<T> {
  const { data: s } = await supabase.auth.getSession();
  const url = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/admin-players`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
      Authorization: `Bearer ${s.session?.access_token ?? ""}`,
    },
    body: JSON.stringify(body),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json.error ?? "Request failed");
  return json as T;
}
