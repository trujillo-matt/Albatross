"use client";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";
import { useAdminSession } from "@/lib/useAdmin";
import { MATCH_LABEL, type MatchType, type Tournament } from "@/lib/types";
import { defaultPointsToWin } from "@/lib/draft";
import AdminSignIn from "@/components/AdminSignIn";

const FORMATS = Object.keys(MATCH_LABEL) as MatchType[];

export default function AdminHome() {
  const { user, ready } = useAdminSession();
  const router = useRouter();
  const [list, setList] = useState<Tournament[]>([]);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [n, setN] = useState(3);
  const [courses, setCourses] = useState<string[]>(["", "", ""]);
  const [formats, setFormats] = useState<MatchType[]>(["best_ball", "best_ball", "best_ball"]);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    const { data: mine } = await supabase.from("tournament_players").select("tournament_id").eq("user_id", user.id).eq("is_admin", true);
    const ids = (mine ?? []).map((m) => m.tournament_id);
    const { data: created } = await supabase.from("tournaments").select("*").eq("creator_user_id", user.id);
    const { data: coAdmin } = ids.length ? await supabase.from("tournaments").select("*").in("id", ids) : { data: [] as Tournament[] };
    const all = new Map<string, Tournament>();
    [...(created ?? []), ...(coAdmin ?? [])].forEach((t) => all.set(t.id, t));
    setList([...all.values()]);
  }, [user]);
  useEffect(() => { load(); }, [load]);

  const setCount = (count: number) => {
    const c = Math.max(1, Math.min(18, count));
    setN(c);
    setCourses((x) => Array.from({ length: c }, (_, i) => x[i] ?? ""));
    setFormats((x) => Array.from({ length: c }, (_, i) => x[i] ?? "best_ball"));
  };

  const create = async () => {
    if (!user) return;
    setErr(null);
    const { data: t, error } = await supabase.from("tournaments").insert({
      name: name.trim(), creator_user_id: user.id, match_type: formats[0], total_matches: n,
      points_to_win: defaultPointsToWin(n),
    }).select().single();
    if (error || !t) { setErr(error?.message ?? "Could not create"); return; }
    const rows = courses.map((c, i) => ({ tournament_id: t.id, course_name: c.trim(), round_number: i + 1, match_type: formats[i] }));
    const c1 = await supabase.from("tournament_courses").insert(rows);
    const c2 = await supabase.from("tournament_players").insert({ tournament_id: t.id, user_id: user.id, invite_status: "accepted", is_admin: true });
    if (c1.error || c2.error) { setErr((c1.error ?? c2.error)!.message); return; }
    router.push(`/admin/${t.id}`);
  };

  if (!ready) return <p className="muted">Loading...</p>;
  if (!user) return <AdminSignIn />;

  return (
    <div className="space-y-4">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-brand">Your tournaments</h1>
        <button className="muted underline" onClick={() => supabase.auth.signOut()}>Sign out</button>
      </header>
      {list.map((t) => (
        <Link key={t.id} href={`/admin/${t.id}`} className="card flex items-center justify-between">
          <div><div className="font-bold">{t.name}</div><div className="muted">{t.total_matches} matches</div></div>
          <span className="rounded-full bg-stone-100 px-3 py-1 text-xs">{t.status}</span>
        </Link>
      ))}
      {list.length === 0 && <p className="muted">No tournaments yet.</p>}

      {!creating ? <button className="btn w-full" onClick={() => setCreating(true)}>New tournament</button> : (
        <div className="card space-y-3">
          <h2 className="h2">New tournament</h2>
          <input className="input" placeholder="Name, e.g. Ryder Cup 2026" value={name} onChange={(e) => setName(e.target.value)} />
          <label className="muted block">Matches (1 to 18)
            <input className="input mt-1" type="number" min={1} max={18} value={n} onChange={(e) => setCount(Number(e.target.value) || 1)} />
          </label>
          <p className="muted">Points to win: {defaultPointsToWin(n).toFixed(1)}</p>
          {courses.map((c, i) => (
            <div key={i} className="space-y-1">
              <div className="muted">Match {i + 1}</div>
              <input className="input" placeholder="Course name" value={c} onChange={(e) => setCourses(courses.map((x, j) => (j === i ? e.target.value : x)))} />
              <select className="input" value={formats[i]} onChange={(e) => setFormats(formats.map((x, j) => (j === i ? (e.target.value as MatchType) : x)))}>
                {FORMATS.map((f) => <option key={f} value={f}>{MATCH_LABEL[f]}</option>)}
              </select>
            </div>
          ))}
          <div className="flex gap-2">
            <button className="btn flex-1" disabled={!name.trim()} onClick={create}>Create</button>
            <button className="btn-ghost" onClick={() => setCreating(false)}>Cancel</button>
          </div>
          {err && <p className="text-sm text-red-600">{err}</p>}
        </div>
      )}
    </div>
  );
}
