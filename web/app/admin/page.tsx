"use client";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";
import { useAdminSession } from "@/lib/useAdmin";
import { type MatchType, type Tournament } from "@/lib/types";
import { FORMAT } from "@/lib/labels";
import { defaultPointsToWin } from "@/lib/draft";
import AdminSignIn from "@/components/AdminSignIn";
import Page from "@/components/Page";
import { TournamentStatusLabel } from "@/components/ui";
import { findCourse, loadCourses, type CatalogCourse } from "@/lib/courses";

const FORMATS = Object.keys(FORMAT) as MatchType[];

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
  const [catalog, setCatalog] = useState<CatalogCourse[]>([]);
  useEffect(() => { loadCourses().then(setCatalog); }, []);

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
    const rows = courses.map((c, i) => {
      const match = findCourse(catalog, c);
      return { tournament_id: t.id, course_name: match?.name ?? c.trim(), round_number: i + 1, match_type: formats[i], ...(match ? { course_id: match.id } : {}) };
    });
    const c1 = await supabase.from("tournament_courses").insert(rows);
    const c2 = await supabase.from("tournament_players").insert({ tournament_id: t.id, user_id: user.id, invite_status: "accepted", is_admin: true });
    if (c1.error || c2.error) { setErr((c1.error ?? c2.error)!.message); return; }
    router.push(`/admin/${t.id}`);
  };

  if (!ready) return <Page><p className="muted">Loading</p></Page>;
  if (!user) return <Page><AdminSignIn /></Page>;

  return (
    <Page wide>
      <div className="space-y-6">
        <header className="flex items-end justify-between gap-4">
          <h1 className="h1">Your tournaments</h1>
          <button className="btn-ghost btn-sm" onClick={() => supabase.auth.signOut()}>Sign out</button>
        </header>

        {list.length > 0 && (
          <div className="card overflow-hidden p-0">
            <ul className="rows">
              {list.map((t) => (
                <li key={t.id}>
                  <Link href={`/admin/${t.id}`} className="pick">
                    <span><span className="text-stone-900">{t.name}</span><span className="muted block"><span className="tnum">{t.total_matches}</span> matches</span></span>
                    <TournamentStatusLabel status={t.status} />
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        )}
        {list.length === 0 && <p className="muted">No tournaments yet</p>}

        {!creating ? <button className="btn w-full sm:w-auto" onClick={() => setCreating(true)}>New tournament</button> : (
          <div className="card max-w-2xl space-y-4">
            <h2 className="h2">New tournament</h2>
            <input className="input" aria-label="Tournament name" placeholder="Name, for example Ryder Cup 2026" value={name} onChange={(e) => setName(e.target.value)} />
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="label block">Matches, 1 to 18
                <input className="input mt-1" type="number" min={1} max={18} value={n} onChange={(e) => setCount(Number(e.target.value) || 1)} />
              </label>
              <div className="label">Points to win<div className="num mt-3 text-3xl text-stone-900">{defaultPointsToWin(n).toFixed(1)}</div></div>
            </div>
            <datalist id="course-list">{catalog.map((c) => <option key={c.id} value={c.name} />)}</datalist>
            <ul className="rows">
              {courses.map((c, i) => (
                <li key={i} className="space-y-2 py-3">
                  <div className="muted">Match <span className="tnum">{i + 1}</span></div>
                  <input className="input" list="course-list" aria-label={`Course for match ${i + 1}`} placeholder="Course name. Pick from the list for real pars" value={c} onChange={(e) => setCourses(courses.map((x, j) => (j === i ? e.target.value : x)))} />
                  <select className="input" aria-label={`Format for match ${i + 1}`} value={formats[i]} onChange={(e) => setFormats(formats.map((x, j) => (j === i ? (e.target.value as MatchType) : x)))}>
                    {FORMATS.map((f) => <option key={f} value={f}>{FORMAT[f]}</option>)}
                  </select>
                </li>
              ))}
            </ul>
            <div className="flex gap-2">
              <button className="btn flex-1" disabled={!name.trim()} onClick={create}>Create tournament</button>
              <button className="btn-ghost" onClick={() => setCreating(false)}>Cancel</button>
            </div>
            {err && <p role="alert" className="text-sm text-bad">{err}</p>}
          </div>
        )}
      </div>
    </Page>
  );
}
