"use client";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { callAdminFunction, useAdminSession } from "@/lib/useAdmin";
import { useTournament } from "@/lib/useTournament";
import { draftPickCount, orderedTeams } from "@/lib/draft";
import type { RoundRow, TMatchup, TournamentData } from "@/lib/types";
import { FORMAT, shortDateTime } from "@/lib/labels";
import { downloadText, toCsv } from "@/lib/csv";
import { formatCode } from "@/lib/code";
import Standings from "@/components/Standings";
import DayBoard from "@/components/DayBoard";
import { courseForMatch } from "@/lib/sessions";
import AdminSignIn from "@/components/AdminSignIn";
import CodeCard from "@/components/CodeCard";
import Page from "@/components/Page";
import { CaptainBadge, CheckIcon, ChevronLeftIcon, Dot, MatchupStatusLabel, TournamentStatusLabel } from "@/components/ui";

type Tab = "overview" | "roster" | "vote" | "matches" | "scores" | "standings" | "audit";
const TAB_LABEL: Record<Tab, string> = {
  overview: "Overview", roster: "Roster", vote: "Vote and draft", matches: "Matches", scores: "Scores", standings: "Standings", audit: "Audit log",
};
interface CodeStatus { user_id: string; status: string; code_hint: string | null; last_used_at: string | null }
type Act = (fn: () => PromiseLike<{ error: { message: string } | null }>) => Promise<void>;

export default function AdminTournament() {
  const { id } = useParams<{ id: string }>();
  const { user, ready } = useAdminSession();
  const { data, error, reload } = useTournament(id);
  const [tab, setTab] = useState<Tab>("overview");
  const [msg, setMsg] = useState<string | null>(null);
  const router = useRouter();
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  if (!ready) return <Page wide><p className="muted">Loading</p></Page>;
  if (!user) return <Page><AdminSignIn /></Page>;
  if (error) return <Page wide><p role="alert" className="text-bad">{error}</p></Page>;
  if (!data) return <Page wide><p className="muted">Loading</p></Page>;

  const isAdmin = data.tournament.creator_user_id === user.id || data.players.some((p) => p.user_id === user.id && p.is_admin);
  if (!isAdmin) return <Page wide><p role="alert" className="text-bad">You are not an admin of this tournament</p></Page>;

  const act: Act = async (fn) => {
    setMsg(null);
    const { error } = await fn();
    if (error) setMsg(error.message);
    reload();
  };

  // Only the person who created the tournament can delete it; the database enforces the same rule.
  const canDelete = data.tournament.creator_user_id === user.id;
  const deleteTournament = async () => {
    setMsg(null);
    const { error } = await supabase.from("tournaments").delete().eq("id", data.tournament.id);
    if (error) { setMsg(error.message); setConfirmingDelete(false); return; }
    router.push("/admin");
  };

  const tabs = Object.keys(TAB_LABEL) as Tab[];
  return (
    <Page wide>
      <div className="space-y-6">
        <header className="space-y-3 print:hidden">
          <Link href="/admin" className="inline-flex items-center gap-1 text-sm text-stone-500 transition-colors duration-150 ease-out hover:text-stone-900">
            <ChevronLeftIcon />All tournaments
          </Link>
          <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
            <h1 className="h1">{data.tournament.name}</h1>
            <TournamentStatusLabel status={data.tournament.status} />
            {canDelete && !confirmingDelete && <button className="btn-ghost btn-sm ml-auto text-bad" onClick={() => setConfirmingDelete(true)}>Delete tournament</button>}
          </div>
          {confirmingDelete && (
            <div role="alertdialog" aria-label="Delete tournament" className="card space-y-3">
              <p className="text-stone-900">Delete tournament?</p>
              <p className="muted">“{data.tournament.name}” and all its data will be permanently deleted. This cannot be undone</p>
              <div className="flex gap-2">
                <button className="btn-sm rounded-lg bg-bad px-3 py-2 text-white" onClick={deleteTournament}>Delete</button>
                <button className="btn-ghost btn-sm" onClick={() => setConfirmingDelete(false)}>Cancel</button>
              </div>
            </div>
          )}
        </header>
        <nav className="tabs print:hidden" aria-label="Sections">
          {tabs.map((t) => (
            <button key={t} className="tab" aria-current={tab === t ? "page" : undefined} onClick={() => setTab(t)}>{TAB_LABEL[t]}</button>
          ))}
        </nav>
        {msg && <p role="alert" className="text-sm text-bad print:hidden">{msg}</p>}
        {tab === "overview" && <Overview data={data} act={act} />}
        {tab === "roster" && <Roster data={data} reload={reload} setMsg={setMsg} />}
        {tab === "vote" && <VoteDraft data={data} act={act} setMsg={setMsg} reload={reload} />}
        {tab === "matches" && <Matches data={data} act={act} userId={user?.id ?? null} reload={reload} />}
        {tab === "scores" && <Scores data={data} setMsg={setMsg} reload={reload} />}
        {tab === "standings" && <div className="max-w-xl"><Standings data={data} /></div>}
        {tab === "audit" && <Audit id={id} />}
      </div>
    </Page>
  );
}

function Overview({ data, act }: { data: TournamentData; act: Act }) {
  const t = data.tournament;
  const accepted = data.players.filter((p) => p.invite_status === "accepted");
  const voters = new Set(data.votes.map((v) => v.voter_user_id)).size;
  const startDraft = () => act(async () => {
    const s = await supabase.from("tournaments").update({ status: "draft", updated_at: new Date().toISOString() }).eq("id", t.id);
    if (s.error) return s;
    return supabase.from("tournament_teams").insert([
      { tournament_id: t.id, name: "Team A", side: "A" },
      { tournament_id: t.id, name: "Team B", side: "B" },
    ]);
  });
  const stat = (n: string, label: string) => (
    <div><div className="num text-3xl text-stone-900">{n}</div><div className="muted">{label}</div></div>
  );
  return (
    <div className="grid gap-4 md:grid-cols-2">
      <div className="space-y-4">
        <div className="card grid grid-cols-3 gap-4">
          {stat(String(accepted.length), "Players")}{stat(String(t.total_matches), "Matches")}{stat(Number(t.points_to_win).toFixed(1), "To win")}
        </div>
        <div className="card space-y-3">
          <h2 className="h2">Next step</h2>
          {t.status === "setup" && <>
            <p className="muted">Add players on the Roster tab, then start the captain vote. You need at least 2 players</p>
            <button className="btn w-full" disabled={accepted.length < 2} onClick={startDraft}>Start captain vote and draft</button></>}
          {t.status === "draft" && <p className="muted"><span className="tnum">{voters}</span> of <span className="tnum">{accepted.length}</span> players have voted. Finalize on the Vote and draft tab</p>}
          {t.status === "active" && <p className="muted">The tournament is under way. Run the callouts on the Matches tab and watch cards come in on the Scores tab</p>}
          {t.status === "complete" && <p className="muted">The tournament is complete</p>}
        </div>
      </div>
      <div className="space-y-4">
        <SpectatorLink id={t.id} />
        <div className="card">
          <h2 className="h2">Courses</h2>
          <ul className="rows mt-2">
            {data.sessions.length > 0 ? data.sessions.map((x) => (
              <li key={x.id} className="row"><span>Day <span className="tnum">{x.day_number}</span>{x.label ? `, ${x.label}` : ""}, {x.course_name || "To be set"}</span><span className="muted">{FORMAT[x.match_type]}{x.match_count ? <>, <span className="tnum">{x.match_count}</span> matches</> : ""}</span></li>
            )) : data.courses.map((c) => (
              <li key={c.id} className="row"><span>Round <span className="tnum">{c.round_number}</span>, {c.course_name || "To be set"}</span><span className="muted">{c.match_type ? FORMAT[c.match_type] : ""}</span></li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}

function Roster({ data, reload, setMsg }: { data: TournamentData; reload: () => void; setMsg: (m: string | null) => void }) {
  const [name, setName] = useState("");
  const [bulk, setBulk] = useState("");
  const [busy, setBusy] = useState(false);
  const [codes, setCodes] = useState<CodeStatus[]>([]);
  const [issued, setIssued] = useState<{ name: string; code: string }[]>([]);
  const tid = data.tournament.id;

  const loadCodes = useCallback(async () => {
    const { data: rows } = await supabase.rpc("admin_code_status", { p_tournament: tid });
    setCodes((rows as CodeStatus[]) ?? []);
  }, [tid]);
  useEffect(() => { loadCodes(); }, [loadCodes, data.players.length]);

  const create = async (names: string[]) => {
    setBusy(true); setMsg(null);
    for (const n of names) {
      try {
        const r = await callAdminFunction<{ user_id: string; code: string }>({ action: "create_player", tournament_id: tid, display_name: n });
        setIssued((x) => [...x, { name: n, code: r.code }]);
      } catch (e) { setMsg(`${n}: ${e instanceof Error ? e.message : "failed"}`); }
    }
    setName(""); setBulk(""); setBusy(false); reload(); loadCodes();
  };
  const regen = async (userId: string, display: string) => {
    try {
      const r = await callAdminFunction<{ code: string }>({ action: "regenerate_code", tournament_id: tid, user_id: userId });
      setIssued((x) => [...x.filter((i) => i.name !== display), { name: display, code: r.code }]);
      loadCodes();
    } catch (e) { setMsg(e instanceof Error ? e.message : "failed"); }
  };
  const revoke = async (userId: string) => {
    try { await callAdminFunction({ action: "revoke_code", tournament_id: tid, user_id: userId }); loadCodes(); }
    catch (e) { setMsg(e instanceof Error ? e.message : "failed"); }
  };
  const locked = data.tournament.status !== "setup";
  const host = typeof window === "undefined" ? "" : window.location.host;

  return (
    <div className="space-y-6">
      {issued.length > 0 && (
        <section className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
            <div>
              <h2 className="h2">New player cards</h2>
              <p className="muted">Codes are stored hashed, so they cannot be shown again. Print or download them now</p>
            </div>
            <div className="flex gap-2">
              <button className="btn-ghost btn-sm" onClick={() => downloadText("player-codes.csv", toCsv([["name", "code"], ...issued.map((i) => [i.name, formatCode(i.code)])]))}>Download CSV</button>
              <button className="btn btn-sm" onClick={() => window.print()}>Print cards</button>
            </div>
          </div>
          <div className="grid gap-4 sm:grid-cols-2 print:grid-cols-2 print:gap-2">
            {issued.map((i) => <CodeCard key={i.name} tournament={data.tournament.name} player={i.name} code={i.code} host={host} />)}
          </div>
        </section>
      )}
      <div className="grid gap-4 print:hidden lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)] lg:items-start">
        <div className="card space-y-3">
          <h2 className="h2">Add players</h2>
          <p className="muted">Each player gets an account and a login code. Put one name per line to add several</p>
          <textarea className="input" rows={4} aria-label="Player names, one per line" placeholder={"Jane Smith\nMike Jones"} value={bulk} onChange={(e) => setBulk(e.target.value)} />
          <input className="input" aria-label="A single player name" placeholder="Or a single name" value={name} onChange={(e) => setName(e.target.value)} />
          <button className="btn w-full" disabled={busy || locked || !(name.trim() || bulk.trim())}
            onClick={() => create([...bulk.split("\n"), name].map((s) => s.trim()).filter(Boolean))}>
            {busy ? "Creating" : "Create players and codes"}
          </button>
          {locked && <p className="muted">The roster is locked once the draft starts</p>}
        </div>
        <div className="card overflow-hidden p-0">
          <ul className="rows">
            {data.players.map((p) => {
              const c = codes.find((x) => x.user_id === p.user_id);
              return (
                <li key={p.id} className="row px-4">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 text-stone-900">{p.display_name}{p.is_admin && <span className="text-xs text-stone-500">Admin</span>}</div>
                    <div className="muted flex flex-wrap items-center gap-x-2">
                      {c ? <>
                        <span className="inline-flex items-center gap-2"><Dot tone={c.last_used_at ? "live" : "idle"} />{c.last_used_at ? `Signed in ${shortDateTime(c.last_used_at)}` : "Not signed in yet"}</span>
                        <span aria-hidden>·</span>
                        <span>Code {c.status}{c.code_hint ? `, ends ${c.code_hint}` : ""}</span></>
                        : <span>Signs in with email</span>}
                    </div>
                  </div>
                  {c && (
                    <div className="flex shrink-0 gap-2">
                      <button className="btn-ghost btn-sm" onClick={() => regen(p.user_id, p.display_name)}>New code</button>
                      {c.status === "active" && <button className="btn-ghost btn-sm" onClick={() => revoke(p.user_id)}>Revoke</button>}
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        </div>
      </div>
    </div>
  );
}

function VoteDraft({ data, act, setMsg, reload }: { data: TournamentData; act: Act; setMsg: (m: string | null) => void; reload: () => void }) {
  const t = data.tournament;
  const [a, b] = orderedTeams(data.teams);
  const accepted = data.players.filter((p) => p.invite_status === "accepted");
  const captainsSet = !!a?.captain_user_id && !!b?.captain_user_id;
  const undrafted = accepted.filter((p) => !p.team_id);
  const tally = accepted.map((p) => ({ p, n: data.votes.filter((v) => v.nominee_user_id === p.user_id).length })).sort((x, y) => y.n - x.n);
  const [tie, setTie] = useState<{ candidates: string[]; slots: number } | null>(null);
  const [pick, setPick] = useState<string[]>([]);

  const finalize = async (winners?: string[]) => {
    setMsg(null);
    const { error } = await supabase.rpc("finalize_captains", { p_tournament: t.id, p_tiebreak: winners ?? null });
    if (error) {
      const m = error.message.match(/captain_tie: choose (\d+) of \{?([^}]*)\}?/);
      if (m) { setTie({ slots: Number(m[1]), candidates: m[2].split(",").map((s) => s.trim()) }); setPick([]); }
      else setMsg(error.message);
    } else { setTie(null); reload(); }
  };

  // Matches for every session are created by the database from the rosters, then the first lineup is auto-filled.
  const startTournament = () => act(() => supabase.rpc("start_tournament", { p_tournament: t.id }));

  if (t.status === "setup") return <p className="muted">Start the captain vote from the Overview tab first</p>;
  const nameOf = (uid: string) => data.players.find((p) => p.user_id === uid)?.display_name ?? uid.slice(0, 6);

  return (
    <div className="grid gap-4 md:grid-cols-2 md:items-start">
      {!captainsSet && t.status === "draft" && (
        <div className="card space-y-3">
          <div>
            <h2 className="h2">Captain vote</h2>
            <p className="muted"><span className="tnum">{new Set(data.votes.map((v) => v.voter_user_id)).size}</span> of <span className="tnum">{accepted.length}</span> voted. You always see live counts</p>
          </div>
          <ul className="rows">
            {tally.map(({ p, n }) => <li key={p.id} className="row"><span>{p.display_name}</span><span className="num text-xl">{n}</span></li>)}
          </ul>
          <button className="btn w-full" onClick={() => finalize()}>Finalize captains</button>
        </div>
      )}
      {tie && (
        <div className="card space-y-3 ring-2 ring-warn/40">
          <div>
            <h2 className="h2">Break the tie</h2>
            <p className="muted">Choose <span className="tnum">{tie.slots}</span> of these tied nominees</p>
          </div>
          <ul className="rows">
            {tie.candidates.map((c) => {
              const on = pick.includes(c);
              return (
                <li key={c}><button className="pick rounded-lg" aria-pressed={on}
                  onClick={() => setPick((s) => s.includes(c) ? s.filter((x) => x !== c) : s.length < tie.slots ? [...s, c] : s)}>
                  <span>{nameOf(c)}</span>{on && <span className="text-brand-accent"><CheckIcon /></span>}
                </button></li>
              );
            })}
          </ul>
          <button className="btn w-full" disabled={pick.length !== tie.slots} onClick={() => finalize(pick)}>Confirm captains</button>
        </div>
      )}
      {captainsSet && (
        <>
          <div className="grid grid-cols-2 gap-4 md:col-span-2">
            {[a, b].map((tm) => (
              <div key={tm.id} className="card">
                <h2 className="h2">{tm.name}</h2>
                <ul className="mt-2 space-y-1 text-sm text-stone-700">
                  {accepted.filter((p) => p.team_id === tm.id).map((p) => (
                    <li key={p.id}>{p.user_id === tm.captain_user_id && <CaptainBadge />}{p.display_name}</li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
          {t.status === "draft" && undrafted.length > 0 && (
            <div className="card md:col-span-2">
              <h2 className="h2">Assign a player</h2>
              <p className="muted"><span className="tnum">{draftPickCount(accepted, data.teams)}</span> picks made. Use this only if a captain cannot pick</p>
              <ul className="rows mt-2">
                {undrafted.map((p) => (
                  <li key={p.id} className="row">
                    <span>{p.display_name}</span>
                    <span className="flex gap-2">
                      {[a, b].map((tm) => <button key={tm.id} className="btn-ghost btn-sm" onClick={() => act(() => supabase.from("tournament_players").update({ team_id: tm.id }).eq("id", p.id))}>{tm.name}</button>)}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          )}
          {t.status === "draft" && undrafted.length === 0 && <button className="btn md:col-span-2" onClick={startTournament}>Start tournament</button>}
        </>
      )}
    </div>
  );
}

function Matches({ data, act, userId, reload }: { data: TournamentData; act: Act; userId: string | null; reload: () => void }) {
  if (data.sessions.length > 0 && data.matchups.some((m) => m.session_id)) {
    return <DayBoard data={data} userId={userId} isAdmin reload={reload} />;
  }
  // Tournaments started before sessions existed keep the old match-by-match editor.
  return (
    <div className="grid gap-4 lg:grid-cols-2 lg:items-start">
      {data.matchups.length === 0 && <p className="muted">Matches are created when the tournament starts</p>}
      {data.matchups.map((m) => <MatchEditor key={m.id} m={m} data={data} act={act} />)}
    </div>
  );
}

function MatchEditor({ m, data, act }: { m: TMatchup; data: TournamentData; act: Act }) {
  const [a, setA] = useState<string[]>(m.team_a_player_ids);
  const [b, setB] = useState<string[]>(m.team_b_player_ids);
  const pool = (tid: string) => data.players.filter((p) => p.team_id === tid);
  const toggle = (list: string[], set: (x: string[]) => void, id: string) =>
    set(list.includes(id) ? list.filter((x) => x !== id) : list.length < 2 ? [...list, id] : list);
  const valid = a.length > 0 && a.length === b.length;
  const side = (tid: string, sel: string[], set: (x: string[]) => void) => (
    <div className="min-w-0 flex-1">
      <div className="muted mb-2">{data.teams.find((t) => t.id === tid)?.name}</div>
      <ul className="divide-y divide-hair overflow-hidden rounded-lg ring-1 ring-hair">
        {pool(tid).map((p) => (
          <li key={p.id}><button className="pick py-2 text-sm" aria-pressed={sel.includes(p.user_id)} disabled={m.status === "complete"} onClick={() => toggle(sel, set, p.user_id)}>
            <span className="truncate">{p.display_name}</span>{sel.includes(p.user_id) && <span className="text-brand-accent"><CheckIcon /></span>}
          </button></li>
        ))}
      </ul>
    </div>
  );
  return (
    <div className="card space-y-4">
      <div className="flex items-center justify-between gap-3">
        <h2 className="h2">Match <span className="tnum">{m.matchup_number}</span>, {FORMAT[m.match_type]}</h2>
        <MatchupStatusLabel status={m.status} />
      </div>
      <div className="flex gap-3">{side(m.team_a_id, a, setA)}{side(m.team_b_id, b, setB)}</div>
      {m.status !== "complete" && (
        <>
          <button className="btn w-full" disabled={!valid}
            onClick={() => act(() => supabase.rpc("set_pairings", { p_matchup: m.id, p_team_a: a, p_team_b: b }))}>
            {m.status === "pending" ? "Confirm pairings" : "Update pairings"}
          </button>
          {!valid && <p className="muted">Pick the same number of players (1 or 2) on each side</p>}
        </>
      )}
    </div>
  );
}

function Scores({ data, setMsg, reload }: { data: TournamentData; setMsg: (m: string | null) => void; reload: () => void }) {
  const [rounds, setRounds] = useState<(RoundRow & { matchup_id: string })[]>([]);
  const load = useCallback(async () => {
    const ids = data.matchups.map((m) => m.id);
    if (!ids.length) return;
    const { data: links } = await supabase.from("tournament_matchup_rounds").select("round_id").in("matchup_id", ids);
    const rids = (links ?? []).map((l) => l.round_id);
    if (!rids.length) { setRounds([]); return; }
    const { data: rs } = await supabase.from("rounds").select("*").in("id", rids);
    setRounds((rs as (RoundRow & { matchup_id: string })[]) ?? []);
  }, [data.matchups]);
  useEffect(() => { load(); const t = setInterval(load, 15000); return () => clearInterval(t); }, [load]);

  const nameOf = (uid: string) => data.players.find((p) => p.user_id === uid)?.display_name ?? "Player";
  const edit = async (r: RoundRow, hole: number) => {
    const v = prompt(`New score for hole ${hole + 1} (leave blank to clear)`, String(r.scores[hole] ?? ""));
    if (v === null) return;
    const reason = prompt("Reason for this change (required, saved to the audit log)");
    if (!reason) return;
    const { error } = await supabase.rpc("admin_set_hole_score", { p_round: r.id, p_hole: hole + 1, p_strokes: v === "" ? null : Number(v), p_reason: reason });
    if (error) setMsg(error.message); else load();
  };
  const assignScorer = async (mid: string, uid: string) => {
    const { error } = await supabase.rpc("set_scorer", { p_matchup: mid, p_scorer: uid || null });
    if (error) setMsg(error.message); else { setMsg(null); reload(); }
  };
  const recompute = async (mid: string) => {
    const { error } = await supabase.rpc("admin_recompute_matchup", { p_matchup: mid });
    if (error) setMsg(error.message); else { setMsg(null); reload(); }
  };
  const exportResults = () => {
    const team = (id: string) => data.teams.find((t) => t.id === id)?.name ?? "";
    downloadText(`${data.tournament.name}-results.csv`, toCsv([
      ["match", "format", "course", "team A", "team B", "points A", "points B", "status"],
      ...data.matchups.map((m) => [m.matchup_number, FORMAT[m.match_type], courseForMatch(data, m).name ?? "",
        team(m.team_a_id), team(m.team_b_id), m.points_team_a, m.points_team_b, m.status]),
    ]));
  };
  const exportCards = () => downloadText(`${data.tournament.name}-scorecards.csv`, toCsv([
    ["match", "player", "status", ...Array.from({ length: 18 }, (_, i) => `H${i + 1}`), "total"],
    ...rounds.map((r) => [data.matchups.find((m) => m.id === r.matchup_id)?.matchup_number ?? "", nameOf(r.user_id), r.status,
      ...r.scores, r.scores.reduce<number>((s, v) => s + (v ?? 0), 0)]),
  ]));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        <button className="btn-ghost btn-sm" onClick={exportResults}>Export results CSV</button>
        <button className="btn-ghost btn-sm" onClick={exportCards}>Export scorecards CSV</button>
      </div>
      <div className="grid gap-4 lg:grid-cols-2 lg:items-start">
        {data.matchups.map((m) => (
          <div key={m.id} className="card space-y-4">
            <div className="flex items-center justify-between gap-3">
              <h2 className="h2">Match <span className="tnum">{m.matchup_number}</span></h2>
              <button className="btn-ghost btn-sm" onClick={() => recompute(m.id)}>Recompute result</button>
            </div>
            {m.status === "active" && (
              <label className="flex items-center justify-between gap-3 text-sm text-stone-600">
                <span>Keeps score for the group</span>
                <select className="input w-auto max-w-[60%] py-2 text-sm" aria-label={`Scorer for match ${m.matchup_number}`}
                  value={m.scorer_user_id ?? ""} onChange={(e) => assignScorer(m.id, e.target.value)}>
                  <option value="">Each player scores their own card</option>
                  {[...m.team_a_player_ids, ...m.team_b_player_ids].map((uid) => <option key={uid} value={uid}>{nameOf(uid)}</option>)}
                </select>
              </label>
            )}
            {rounds.filter((r) => r.matchup_id === m.id).map((r) => (
              <div key={r.id} className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-stone-900">{nameOf(r.user_id)}</span>
                  <span className="muted inline-flex items-center gap-2"><Dot tone={r.status === "completed" ? "idle" : "live"} />{r.status === "completed" ? "Submitted" : "In progress"}
                    <span className="num text-base text-stone-900">{r.scores.reduce<number>((s, v) => s + (v ?? 0), 0)}</span></span>
                </div>
                <div className="grid grid-cols-9 gap-1 text-center">
                  {r.scores.map((s, i) => (
                    <button key={i} aria-label={`Edit hole ${i + 1}`} onClick={() => edit(r, i)}
                      className="rounded-md bg-stone-100 py-1 transition-colors duration-150 ease-out hover:bg-stone-200">
                      <div className="num text-xs text-stone-500">{i + 1}</div><div className="num">{s ?? "·"}</div>
                    </button>
                  ))}
                </div>
              </div>
            ))}
            {!rounds.some((r) => r.matchup_id === m.id) && <p className="muted">No scorecards started</p>}
          </div>
        ))}
      </div>
    </div>
  );
}

function SpectatorLink({ id }: { id: string }) {
  const [token, setToken] = useState<string | null | undefined>(undefined);
  const [err, setErr] = useState<string | null>(null);
  const set = async (enable: boolean) => {
    setErr(null);
    const { data, error } = await supabase.rpc("set_spectator_link", { p_tournament: id, p_enable: enable });
    if (error) setErr(error.message); else setToken(enable ? (data as string) : null);
  };
  const url = token ? `${window.location.origin}/watch/${token}` : null;
  return (
    <div className="card space-y-3">
      <h2 className="h2">Spectator link</h2>
      <p className="muted">A read-only live standings page for anyone with the link. Turning it off breaks the old link</p>
      {url && <input className="input font-mono text-xs" aria-label="Spectator link" readOnly value={url} onFocus={(e) => e.currentTarget.select()} />}
      <div className="flex gap-2">
        <button className="btn-ghost flex-1" onClick={() => set(true)}>{token ? "Show link" : "Enable link"}</button>
        {token && <button className="btn-ghost" onClick={() => set(false)}>Turn off</button>}
      </div>
      {err && <p role="alert" className="text-sm text-bad">{err}</p>}
    </div>
  );
}

interface AuditRow { created_at: string; actor_name: string | null; action: string; target_type: string | null; reason: string | null; before: unknown; after: unknown }
function Audit({ id }: { id: string }) {
  const [rows, setRows] = useState<AuditRow[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    supabase.rpc("admin_audit_log", { p_tournament: id }).then(({ data, error }) => {
      if (error) setErr(error.message); else setRows((data as AuditRow[]) ?? []);
    });
  }, [id]);
  if (err) return <p role="alert" className="text-sm text-bad">{err}</p>;
  if (!rows) return <p className="muted">Loading</p>;
  const sentence = (a: string) => { const s = a.replace(/_/g, " "); return s.charAt(0).toUpperCase() + s.slice(1); };
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="h2">Audit log</h2>
        <button className="btn-ghost btn-sm" onClick={() => downloadText(`audit-${id}.csv`, toCsv([["time", "who", "action", "target", "reason"], ...rows.map((r) => [r.created_at, r.actor_name, r.action, r.target_type, r.reason])]))}>Export CSV</button>
      </div>
      {rows.length === 0 && <p className="muted">No admin changes recorded yet</p>}
      {rows.length > 0 && (
        <div className="card overflow-hidden p-0">
          <ul className="rows">
            {rows.map((r, i) => (
              <li key={i} className="space-y-1 px-4 py-3 text-sm">
                <div className="flex items-center justify-between gap-3"><span className="text-stone-900">{sentence(r.action)}</span><span className="muted">{shortDateTime(r.created_at)}</span></div>
                <div className="muted">{r.actor_name ?? "Unknown"}{r.reason ? `, ${r.reason}` : ""}</div>
                {r.before != null && r.after != null && <div className="font-mono text-xs text-stone-500">{JSON.stringify(r.before)} to {JSON.stringify(r.after)}</div>}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
