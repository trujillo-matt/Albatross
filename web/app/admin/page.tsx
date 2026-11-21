"use client";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";
import { useAdminSession } from "@/lib/useAdmin";
import { type MatchType, type Tournament } from "@/lib/types";
import { FORMAT } from "@/lib/labels";
import { PRESETS, planToSessionRows, planTotals, sessionMatchCount, type PlanDay } from "@/lib/sessions";
import AdminSignIn from "@/components/AdminSignIn";
import NewsFeed from "@/components/NewsFeed";
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
  const [plan, setPlan] = useState<PlanDay[]>([{ course: "", sessions: [{ label: "AM", match_type: "alternate_shot" }, { label: "PM", match_type: "best_ball" }] }]);
  const [perTeam, setPerTeam] = useState(8);
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

  const editDay = (di: number, fn: (d: PlanDay) => PlanDay) => setPlan((p) => p.map((d, i) => (i === di ? fn(d) : d)));
  const totals = planTotals(plan.flatMap((d) => d.sessions), perTeam, perTeam);

  const create = async () => {
    if (!user) return;
    setErr(null);
    const first = plan[0].sessions[0].match_type;
    // Matches are created from the rosters when the tournament starts; these totals are a placeholder until then.
    const { data: t, error } = await supabase.from("tournaments").insert({
      name: name.trim(), creator_user_id: user.id, match_type: first, total_matches: Math.max(1, totals.matches), points_to_win: totals.pointsToWin,
    }).select().single();
    if (error || !t) { setErr(error?.message ?? "Could not create"); return; }
    // One course row per day (what older screens and the player hub read), plus the sessions that drive the matches.
    const courseRows = plan.map((d, i) => {
      const match = findCourse(catalog, d.course);
      return { tournament_id: t.id, course_name: match?.name ?? d.course.trim(), round_number: i + 1, match_type: d.sessions[0].match_type, ...(match ? { course_id: match.id } : {}) };
    });
    const sessionRows = planToSessionRows(t.id, plan).map((r) => {
      const match = findCourse(catalog, r.course_name ?? "");
      return { ...r, course_name: match?.name ?? r.course_name, ...(match ? { course_id: match.id } : {}) };
    });
    const c1 = await supabase.from("tournament_courses").insert(courseRows);
    const c2 = await supabase.from("tournament_players").insert({ tournament_id: t.id, user_id: user.id, invite_status: "accepted", is_admin: true });
    const c3 = await supabase.from("tournament_sessions").insert(sessionRows);
    if (c1.error || c2.error || c3.error) { setErr((c1.error ?? c2.error ?? c3.error)!.message); return; }
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

        {list.length > 0 && <NewsFeed tournamentIds={list.map((t) => t.id)} names={Object.fromEntries(list.map((t) => [t.id, t.name]))} />}

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
            <div className="flex flex-wrap items-end gap-3">
              <label className="label block">Players per team (preview only)
                <input className="input mt-1 w-28" type="number" min={2} max={24} value={perTeam} onChange={(e) => setPerTeam(Math.max(2, Number(e.target.value) || 2))} />
              </label>
              <div className="label">Matches<div className="num mt-1 text-3xl text-stone-900">{totals.matches}</div></div>
              <div className="label">Points to win<div className="num mt-1 text-3xl text-stone-900">{totals.pointsToWin.toFixed(1)}</div></div>
            </div>
            <p className="muted">Matches are worked out from who is on each team when you start. The numbers above are a preview</p>
            <datalist id="course-list">{catalog.map((c) => <option key={c.id} value={c.name} />)}</datalist>
            <ul className="space-y-4">
              {plan.map((d, di) => (
                <li key={di} className="space-y-3 rounded-lg p-3 ring-1 ring-hair">
                  <div className="flex items-center justify-between gap-2">
                    <span className="h2">Day <span className="tnum">{di + 1}</span></span>
                    {plan.length > 1 && <button className="btn-ghost btn-sm" onClick={() => setPlan(plan.filter((_, i) => i !== di))}>Remove day</button>}
                  </div>
                  <input className="input" list="course-list" aria-label={`Course for day ${di + 1}`} placeholder="Course name. Pick from the list for real pars" value={d.course}
                    onChange={(e) => editDay(di, (x) => ({ ...x, course: e.target.value }))} />
                  <ul className="rows">
                    {d.sessions.map((x, si) => (
                      <li key={si} className="flex flex-wrap items-center gap-2 py-2">
                        <input className="input w-24" aria-label={`Name of session ${si + 1} on day ${di + 1}`} placeholder="AM" value={x.label}
                          onChange={(e) => editDay(di, (y) => ({ ...y, sessions: y.sessions.map((z, k) => (k === si ? { ...z, label: e.target.value } : z)) }))} />
                        <select className="input flex-1" aria-label={`Format of session ${si + 1} on day ${di + 1}`} value={x.match_type}
                          onChange={(e) => editDay(di, (y) => ({ ...y, sessions: y.sessions.map((z, k) => (k === si ? { ...z, match_type: e.target.value as MatchType } : z)) }))}>
                          {FORMATS.map((f) => <option key={f} value={f}>{FORMAT[f]}</option>)}
                        </select>
                        <span className="muted tnum w-24 text-right">{sessionMatchCount(perTeam, perTeam, x.match_type)} matches</span>
                        {d.sessions.length > 1 && <button className="btn-ghost btn-sm" aria-label="Remove session" onClick={() => editDay(di, (y) => ({ ...y, sessions: y.sessions.filter((_, k) => k !== si) }))}>Remove</button>}
                      </li>
                    ))}
                  </ul>
                  <div className="flex flex-wrap gap-2">
                    {d.sessions.length < 3 && <button className="btn-ghost btn-sm" onClick={() => editDay(di, (y) => ({ ...y, sessions: [...y.sessions, { label: "", match_type: "best_ball" }] }))}>Add session</button>}
                    {PRESETS.map((pr) => <button key={pr.id} className="btn-ghost btn-sm" onClick={() => editDay(di, (y) => ({ ...y, sessions: pr.days.map((z) => ({ ...z })) }))}>{pr.name}</button>)}
                  </div>
                </li>
              ))}
            </ul>
            {plan.length < 7 && <button className="btn-ghost" onClick={() => setPlan([...plan, { course: "", sessions: plan[plan.length - 1].sessions.map((z) => ({ ...z })) }])}>Add day</button>}
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
