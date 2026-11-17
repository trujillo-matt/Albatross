"use client";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { useTournament, useUserId } from "@/lib/useTournament";
import { MATCH_LABEL, type RoundRow } from "@/lib/types";
import { findCourse, loadCourses } from "@/lib/courses";
import { enqueue, flush, pendingCount } from "@/lib/scoreQueue";
import { matchPlayStatus } from "@/lib/scoring";

const DEFAULT_PARS = [4, 4, 3, 4, 5, 3, 4, 4, 5, 4, 3, 4, 5, 4, 3, 4, 5, 4];

export default function MatchPage() {
  const { id, mid } = useParams<{ id: string; mid: string }>();
  const router = useRouter();
  const { userId, ready } = useUserId();
  const { data } = useTournament(id);
  const [round, setRound] = useState<RoundRow | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [hole, setHole] = useState(0);
  const [pending, setPending] = useState(0);
  const [msg, setMsg] = useState<string | null>(null);
  const [live, setLive] = useState<string | null>(null);

  useEffect(() => { if (ready && !userId) router.replace("/join"); }, [ready, userId, router]);

  const matchup = data?.matchups.find((m) => m.id === mid);
  const mine = !!userId && !!matchup && (matchup.team_a_player_ids.includes(userId) || matchup.team_b_player_ids.includes(userId));

  const loadRound = useCallback(async () => {
    if (!userId) return;
    const { data: r } = await supabase.from("rounds").select("*").eq("matchup_id", mid).eq("user_id", userId).limit(1);
    const found = (r?.[0] as RoundRow | undefined) ?? null;
    setRound(found);
    if (found) setHole(Math.max(0, found.scores.findIndex((s) => s === null)));
    setLoaded(true);
  }, [mid, userId]);
  useEffect(() => { loadRound(); }, [loadRound]);

  // Flush queued scores on mount and whenever the connection returns.
  useEffect(() => {
    const run = async () => {
      const r = await flush();
      if (r.rejected.length) setMsg(r.rejected.join("; "));
      setPending(pendingCount());
    };
    run();
    window.addEventListener("online", run);
    return () => window.removeEventListener("online", run);
  }, []);

  // Best effort live status for match play (depends on RLS allowing teammates/opponents to read cards).
  useEffect(() => {
    if (!matchup || matchup.match_type !== "match_play" || !round) return;
    const t = setInterval(async () => {
      const { data: links } = await supabase.from("tournament_matchup_rounds").select("round_id, user_id").eq("matchup_id", mid);
      if (!links?.length) return;
      const { data: rs } = await supabase.from("rounds").select("id, user_id, scores").in("id", links.map((l) => l.round_id));
      if (!rs) return;
      const side = (uid: string) => (matchup.team_a_player_ids.includes(uid) ? "a" : "b");
      const a = rs.filter((r) => side(r.user_id) === "a").map((r) => r.scores);
      const b = rs.filter((r) => side(r.user_id) === "b").map((r) => r.scores);
      const s = matchPlayStatus(a, b);
      setLive(s.thru === 0 ? null : s.up === 0 ? `All square thru ${s.thru}` : `Team ${s.up > 0 ? "A" : "B"} ${Math.abs(s.up)} up thru ${s.thru}`);
    }, 15000);
    return () => clearInterval(t);
  }, [matchup, round, mid]);

  if (!data || !matchup || !userId) return <p className="muted">Loading...</p>;

  const teamName = (tid: string) => data.teams.find((t) => t.id === tid)?.name ?? "Team";
  const nameOf = (uid: string) => data.players.find((p) => p.user_id === uid)?.display_name ?? "Player";
  const courseName = data.courses.find((c) => c.round_number === matchup.matchup_number)?.course_name ?? "Tournament Match";

  const startCard = async () => {
    setMsg(null);
    const list = await loadCourses();
    const courseId = data.courses.find((c) => c.round_number === matchup.matchup_number)?.course_id;
    const catalog = (courseId ? list.find((c) => c.id === courseId) : undefined) ?? findCourse(list, courseName);
    const pars = catalog ? [...catalog.holes].sort((a, b) => a.number - b.number) : null;
    const row = {
      id: crypto.randomUUID(), user_id: userId, course_name: courseName,
      course_id: catalog?.id ?? null,
      course_pars: pars?.map((h) => h.par) ?? null,
      course_handicaps: pars?.map((h) => h.handicap) ?? null,
      course_yardages: pars?.map((h) => h.yardage) ?? null,
      course_rating: catalog?.courseRating ?? null, slope_rating: catalog?.slopeRating ?? null,
      matchup_id: matchup.id, date: new Date().toISOString(),
      scores: Array(18).fill(null), status: "in_progress", updated_at: new Date().toISOString(),
    };
    const { error } = await supabase.from("rounds").insert(row);
    if (error) { setMsg(error.message); return; }
    // Link at start so the database trigger sees it when the round completes.
    const link = await supabase.from("tournament_matchup_rounds").upsert({ matchup_id: matchup.id, round_id: row.id, user_id: userId });
    if (link.error) setMsg(link.error.message);
    loadRound();
  };

  const setScore = (strokes: number | null) => {
    if (!round || round.status === "completed") return;
    const next = [...round.scores]; next[hole] = strokes;
    setRound({ ...round, scores: next });
    enqueue({ roundId: round.id, hole: hole + 1, strokes });
    setPending(pendingCount());
    flush().then(() => setPending(pendingCount()));
    if (strokes !== null && hole < 17) setTimeout(() => setHole((h) => Math.min(17, h + 1)), 150);
  };

  const finish = async () => {
    if (!round) return;
    await flush();
    if (pendingCount(round.id) > 0) { setMsg("Some scores have not synced yet. Reconnect and try again."); return; }
    const { error } = await supabase.from("rounds").update({ status: "completed", updated_at: new Date().toISOString() }).eq("id", round.id);
    if (error) setMsg(error.message); else loadRound();
  };

  const pars = round?.course_pars ?? DEFAULT_PARS;
  const yards = round?.course_yardages?.[hole];
  const filled = round?.scores.filter((s) => s !== null).length ?? 0;
  const total = round?.scores.reduce<number>((s, v) => s + (v ?? 0), 0) ?? 0;
  const parSoFar = round ? round.scores.reduce<number>((s, v, i) => s + (v === null ? 0 : pars[i]), 0) : 0;
  const diff = total - parSoFar;
  const locked = round?.status === "completed";
  const val = round?.scores[hole] ?? null;
  const bigOver = val !== null && val - pars[hole] >= 5;

  return (
    <div className="space-y-4">
      <Link href={`/t/${id}`} className="muted underline">Back</Link>
      <div className="card">
        <div className="flex justify-between">
          <div><div className="font-bold">{teamName(matchup.team_a_id)}</div>
            <div className="muted">{matchup.team_a_player_ids.map(nameOf).join(", ") || "TBD"}</div></div>
          <div className="text-right"><div className="font-bold">{teamName(matchup.team_b_id)}</div>
            <div className="muted">{matchup.team_b_player_ids.map(nameOf).join(", ") || "TBD"}</div></div>
        </div>
        <p className="muted mt-2">Match {matchup.matchup_number} · {MATCH_LABEL[matchup.match_type]} · {courseName}</p>
        {live && <p className="mt-1 font-semibold text-brand-accent">{live}</p>}
        {matchup.status === "complete" && <p className="mt-1 font-bold">Final: {Number(matchup.points_team_a).toFixed(1)} to {Number(matchup.points_team_b).toFixed(1)}</p>}
      </div>

      {matchup.status === "pending" && <p className="muted">Waiting for pairings to be set.</p>}

      {matchup.status !== "pending" && mine && loaded && !round && (
        <div className="space-y-2">
          {matchup.match_type === "scramble" && <p className="muted">Scramble: your team plays one ball, so only one teammate needs to enter the team scorecard.</p>}
          <button className="btn w-full" onClick={startCard}>Start scorecard</button>
        </div>
      )}
      {matchup.status !== "pending" && !mine && <p className="muted">You are not playing in this match.</p>}

      {round && (
        <>
          <div className="card">
            <div className="flex items-baseline justify-between">
              <h2 className="h2">Hole {hole + 1}</h2>
              <span className="muted">Par {pars[hole]}{yards ? ` · ${yards} yds` : ""}</span>
            </div>
            <div className="my-3 text-center text-6xl font-bold">{val ?? "–"}</div>
            {bigOver && !locked && <p className="text-center text-sm text-amber-700">That is {val! - pars[hole]} over par. Tap a different number to change it.</p>}
            {!locked && (
              <div className="grid grid-cols-5 gap-2">
                {Array.from({ length: 10 }, (_, i) => i + 1).map((n) => (
                  <button key={n} onClick={() => setScore(n)} className={`rounded-xl py-4 text-xl font-bold ring-1 ring-stone-300 ${val === n ? "bg-brand text-white" : "bg-white"}`}>{n}</button>
                ))}
                <button onClick={() => setScore(val !== null && val >= 10 && val < 20 ? val + 1 : 11)} className="col-span-4 rounded-xl bg-white py-4 text-sm font-semibold ring-1 ring-stone-300">11 and up (tap to add 1)</button>
                <button onClick={() => setScore(null)} className="rounded-xl bg-white py-4 text-sm ring-1 ring-stone-300">Clear</button>
              </div>
            )}
            <div className="mt-3 flex justify-between">
              <button className="btn-ghost" disabled={hole === 0} onClick={() => setHole(hole - 1)}>Prev</button>
              <button className="btn-ghost" disabled={hole === 17} onClick={() => setHole(hole + 1)}>Next</button>
            </div>
          </div>

          <div className="card">
            <div className="mb-2 flex justify-between text-sm">
              <span>{filled}/18 holes</span>
              <span className="font-bold">{total} ({diff === 0 ? "E" : diff > 0 ? `+${diff}` : diff})</span>
              <span className={pending ? "text-amber-700" : "muted"}>{pending ? `${pending} unsynced` : "Synced"}</span>
            </div>
            <div className="grid grid-cols-9 gap-1 text-center text-sm">
              {round.scores.map((s, i) => (
                <button key={i} onClick={() => setHole(i)} className={`rounded-md py-1 ${i === hole ? "bg-brand text-white" : "bg-stone-100"}`}>
                  <div className="text-[10px] opacity-60">{i + 1}</div>{s ?? "·"}
                </button>
              ))}
            </div>
          </div>

          {!locked ? (
            <button className="btn w-full" disabled={filled < 18} onClick={finish}>Finish and submit scorecard</button>
          ) : (
            <p className="text-center font-semibold text-brand-accent">Scorecard submitted. Only the admin can change it now.</p>
          )}
        </>
      )}
      {msg && <p className="text-sm text-red-600">{msg}</p>}
    </div>
  );
}
