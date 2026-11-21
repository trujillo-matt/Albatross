"use client";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import type { RoundRow, TMatchup, TournamentData } from "@/lib/types";
import { enqueue, flush, pendingCount } from "@/lib/scoreQueue";
import { findCourse, loadCourses } from "@/lib/courses";
import { cardTotal, DEFAULT_PARS, foursomeOf, groupComplete, groupFilled, groupHasAllCards, isTeamCardFormat, matchOf, nextEmptyCell, orderCards, sideOf } from "@/lib/groupScoring";
import { CaptainBadge, CheckIcon, Dot } from "./ui";

interface Props {
  data: TournamentData;
  matchup: TMatchup;
  me: string;
  courseName: string;
  courseId?: string | null;
  /** Called after anything that changes who is scoring or whether the match finished, so the page reloads. */
  onChanged: () => void;
}

/**
 * One player keeps score for the whole group. Shows one of three things:
 *  - nobody is scoring yet: an offer to keep score for everyone,
 *  - I am the scorer: every player's strokes, hole by hole,
 *  - someone else is: a read-only live view of the group's cards.
 */
export default function GroupScoring({ data, matchup, me, courseName, courseId, onChanged }: Props) {
  // The foursome: this match, plus the one it is played alongside in singles formats. One scorer keeps all the cards.
  const group = foursomeOf(matchup, data.matchups);
  const groupKey = group.map((x) => x.id).join(",");
  const scorerId = matchup.scorer_user_id ?? null;
  const iAmScorer = scorerId === me;
  const [cards, setCards] = useState<RoundRow[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [hole, setHole] = useState(0);
  const [active, setActive] = useState(0);
  const [pending, setPending] = useState(0);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const nameOf = (uid: string) => data.players.find((p) => p.user_id === uid)?.display_name ?? "Player";
  const matchFor = (uid: string) => matchOf(group, uid) ?? matchup;
  const teamOf = (uid: string) => { const m = matchFor(uid); return data.teams.find((t) => t.id === (sideOf(m, uid) === "A" ? m.team_a_id : m.team_b_id))?.name ?? "Team"; };
  // A captain's yellow C goes before their own name; a team-card format shows the team name instead.
  const captainMark = (uid: string) => !isTeamCardFormat(matchup.match_type) && data.teams.some((t) => t.captain_user_id === uid) ? <CaptainBadge /> : null;
  const label = (uid: string) => isTeamCardFormat(matchup.match_type) ? teamOf(uid) : nameOf(uid);
  const sub = (uid: string) => { const m = matchFor(uid); return isTeamCardFormat(matchup.match_type)
    ? (sideOf(m, uid) === "A" ? m.team_a_player_ids : m.team_b_player_ids).map(nameOf).join(", ") : teamOf(uid); };

  const load = useCallback(async () => {
    const { data: rs } = await supabase.from("rounds").select("*").in("matchup_id", groupKey.split(","));
    setCards(orderCards(group, (rs as RoundRow[]) ?? []));
    setLoaded(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [groupKey]);

  // Cards for everyone watching or scoring; the scorer's own screen refreshes on every action, watchers poll.
  useEffect(() => {
    if (!scorerId) { setLoaded(true); return; }
    load();
    if (iAmScorer) return;
    const t = setInterval(load, 10000);
    return () => clearInterval(t);
  }, [scorerId, iAmScorer, load]);

  useEffect(() => {
    if (!iAmScorer) return;
    const run = async () => { const r = await flush(); if (r.rejected.length) setErr(r.rejected.join("; ")); setPending(pendingCount()); };
    run();
    window.addEventListener("online", run);
    return () => window.removeEventListener("online", run);
  }, [iAmScorer]);

  // Open on the first empty cell when the scorer arrives (or returns) to a half-finished group.
  useEffect(() => {
    if (!iAmScorer || cards.length === 0) return;
    const first = cards[0].scores[0] === null ? { hole: 0, card: 0 } : nextEmptyCell(cards, 0, 0);
    if (first) { setHole(first.hole); setActive(first.card); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [iAmScorer, loaded]);

  const rpc = async (fn: string, args: Record<string, unknown>) => {
    setBusy(true); setErr(null);
    const { error } = await supabase.rpc(fn, args);
    setBusy(false);
    if (error) { setErr(error.message); return false; }
    return true;
  };

  const volunteer = async () => { if (await rpc("set_scorer", { p_matchup: matchup.id, p_scorer: me })) onChanged(); };
  const stepDown = async () => { if (await rpc("set_scorer", { p_matchup: matchup.id, p_scorer: null })) onChanged(); };

  const start = async () => {
    const list = await loadCourses();
    const catalog = (courseId ? list.find((c) => c.id === courseId) : undefined) ?? findCourse(list, courseName);
    const holes = catalog ? [...catalog.holes].sort((a, b) => a.number - b.number) : null;
    const course = {
      course_name: courseName, course_id: catalog?.id ?? null,
      pars: holes?.map((h) => h.par) ?? null, handicaps: holes?.map((h) => h.handicap) ?? null, yardages: holes?.map((h) => h.yardage) ?? null,
      rating: catalog?.courseRating ?? null, slope: catalog?.slopeRating ?? null,
    };
    if (await rpc("start_group_scoring", { p_matchup: matchup.id, p_course: course })) await load();
  };

  const enter = (strokes: number | null) => {
    const card = cards[active];
    if (!card || card.status === "completed") return;
    const before = card.scores[hole];
    const next = cards.map((c, i) => i === active ? { ...c, scores: c.scores.map((v, h) => (h === hole ? strokes : v)) } : c);
    setCards(next);
    enqueue({ roundId: card.id, hole: hole + 1, strokes });
    setPending(pendingCount());
    flush().then(() => setPending(pendingCount()));
    // Move on only when this was a new entry, so fixing an earlier mistake does not jump you around.
    if (strokes !== null && before === null) {
      const to = nextEmptyCell(next, hole, active);
      if (to) setTimeout(() => { setHole(to.hole); setActive(to.card); }, 120);
    }
  };

  const finish = async () => {
    await flush();
    if (pendingCount() > 0) { setErr("Some scores have not synced yet. Reconnect and try again"); return; }
    if (await rpc("finish_group_scoring", { p_matchup: matchup.id })) { await load(); onChanged(); }
  };

  // ---- 1. Nobody is scoring yet
  if (!scorerId) {
    if (matchup.status !== "active") return null;
    return (
      <div className="card space-y-3">
        <h2 className="h2">Keep score for the whole group</h2>
        <p className="muted">{group.length > 1 ? "One player can enter everyone's strokes in the foursome, across both matches, on a single phone. The others follow along" : "One player can enter everyone's strokes on a single phone. The others follow along"}</p>
        <button className="btn w-full" disabled={busy} onClick={volunteer}>I&apos;ll keep score for the group</button>
        {err && <p role="alert" className="text-sm text-bad">{err}</p>}
      </div>
    );
  }

  const scorerName = nameOf(scorerId);
  const pars = cards[0]?.course_pars ?? DEFAULT_PARS;
  const yards = cards[0]?.course_yardages?.[hole];
  const allThere = groupHasAllCards(group, cards);
  const done = cards.length > 0 && cards.every((c) => c.status === "completed");
  const complete = groupComplete(cards);
  const filled = groupFilled(cards);
  const cur = cards[active];
  const val = cur?.scores[hole] ?? null;
  const pad = (on: boolean) =>
    `num h-14 rounded-lg text-2xl ring-1 transition-[background-color,color,transform] duration-150 ease-out active:scale-[0.97] ${on ? "bg-brand text-paper ring-brand" : "bg-white text-stone-900 ring-hair hover:bg-stone-100"}`;

  const table = (
    <div className="card space-y-3">
      <div className="flex items-center justify-between gap-3">
        <h2 className="h2">Scorecards</h2>
        {iAmScorer && !done && <span className="inline-flex items-center gap-2 text-sm text-stone-600"><Dot tone={pending ? "warn" : "live"} />{pending ? `${pending} unsynced` : "Synced"}</span>}
      </div>
      <div className="-mx-4 overflow-x-auto px-4">
        <table className="w-full min-w-[34rem] border-collapse text-center text-sm">
          <thead>
            <tr className="text-xs text-stone-500">
              <th className="py-2 pr-3 text-left font-normal">Hole</th>
              {Array.from({ length: 18 }, (_, i) => <th key={i} className="tnum w-7 py-2 font-normal">{i + 1}</th>)}
              <th className="py-2 pl-3 text-right font-normal">Total</th>
            </tr>
          </thead>
          <tbody>
            {cards.map((c) => (
              <tr key={c.id} className="border-t border-hair">
                <td className="max-w-[7rem] truncate py-2 pr-3 text-left text-stone-900">{captainMark(c.user_id)}{label(c.user_id)}</td>
                {c.scores.map((s, i) => <td key={i} className="num text-base text-stone-800">{s ?? "·"}</td>)}
                <td className="num pl-3 text-right text-lg text-stone-900">{cardTotal(c.scores)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );

  // ---- 3. Someone else is scoring
  if (!iAmScorer) {
    return (
      <div className="space-y-4">
        <div className="card space-y-1">
          <h2 className="h2">{scorerName} is keeping score for this group</h2>
          <p className="muted">{done ? "The scorecards are submitted" : loaded && cards.length === 0 ? "Scorecards appear once they start" : "Scores appear here as they are entered"}</p>
        </div>
        {cards.length > 0 && table}
      </div>
    );
  }

  // ---- 2. I am the scorer
  return (
    <div className="space-y-4">
      <div className="card flex items-center justify-between gap-3">
        <div>
          <h2 className="h2">You are keeping score for the group</h2>
          <p className="muted">{isTeamCardFormat(matchup.match_type) ? "Enter one score for each side" : "Enter each player's strokes"}</p>
        </div>
        {!done && <button className="btn-ghost btn-sm shrink-0" disabled={busy} onClick={stepDown}>Step down</button>}
      </div>

      {!allThere && (
        <button className="btn w-full" disabled={busy} onClick={start}>Start the group scorecards</button>
      )}

      {allThere && !done && cur && (
        <div className="card space-y-4">
          <div className="flex items-baseline justify-between">
            <h2 className="font-serif text-2xl text-stone-900">Hole <span className="tnum">{hole + 1}</span></h2>
            <span className="muted">Par {pars[hole]}{yards ? ` · ${yards} yds` : ""}</span>
          </div>
          <ul className="divide-y divide-hair overflow-hidden rounded-lg ring-1 ring-hair">
            {cards.map((c, i) => (
              <li key={c.id}>
                <button className="pick" aria-pressed={i === active} onClick={() => setActive(i)}>
                  <span className="min-w-0"><span className="block truncate text-stone-900">{captainMark(c.user_id)}{label(c.user_id)}</span><span className="muted block truncate">{sub(c.user_id)}</span></span>
                  <span className="num text-3xl text-stone-900" aria-label={`${label(c.user_id)}, hole ${hole + 1}`}>{c.scores[hole] ?? "–"}</span>
                </button>
              </li>
            ))}
          </ul>
          <div className="grid grid-cols-5 gap-2">
            {Array.from({ length: 10 }, (_, i) => i + 1).map((n) => (
              <button key={n} onClick={() => enter(n)} aria-pressed={val === n} className={pad(val === n)}>{n}</button>
            ))}
            <button onClick={() => enter(val !== null && val >= 10 && val < 20 ? val + 1 : 11)} aria-pressed={val !== null && val >= 11}
              className={`col-span-4 h-14 rounded-lg text-sm ring-1 transition-[background-color,color,transform] duration-150 ease-out active:scale-[0.98] ${val !== null && val >= 11 ? "bg-brand text-paper ring-brand" : "bg-white text-stone-700 ring-hair hover:bg-stone-100"}`}>
              {val !== null && val >= 11 ? `${val}, tap to add one` : "11 or more"}
            </button>
            <button onClick={() => enter(null)} className="h-14 rounded-lg bg-white text-sm text-stone-600 ring-1 ring-hair transition-[background-color,transform] duration-150 ease-out hover:bg-stone-100 active:scale-[0.98]">Clear</button>
          </div>
          <div className="flex justify-between">
            <button className="btn-ghost" disabled={hole === 0} onClick={() => setHole(hole - 1)}>Previous</button>
            <button className="btn-ghost" disabled={hole === 17} onClick={() => setHole(hole + 1)}>Next</button>
          </div>
        </div>
      )}

      {cards.length > 0 && table}

      {allThere && !done && (
        <div className="space-y-2">
          <p className="muted text-center"><span className="tnum">{filled}</span> of <span className="tnum">{cards.length * 18}</span> scores entered</p>
          <button className="btn w-full" disabled={!complete || busy} onClick={finish}>Finish and submit the group scorecards</button>
        </div>
      )}
      {done && <p className="inline-flex w-full items-center justify-center gap-2 text-sm text-brand-accent"><CheckIcon />Group scorecards submitted. Only an admin can change them now</p>}
      {err && <p role="alert" className="text-sm text-bad">{err}</p>}
    </div>
  );
}
