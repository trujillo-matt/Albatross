"use client";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { callAdminFunction, useAdminSession } from "@/lib/useAdmin";
import { useTournament } from "@/lib/useTournament";
import { draftPickCount, orderedTeams } from "@/lib/draft";
import { MATCH_LABEL, type RoundRow, type TMatchup, type TournamentData } from "@/lib/types";
import { formatCode } from "@/lib/code";
import { downloadText, toCsv } from "@/lib/csv";
import Standings from "@/components/Standings";
import AdminSignIn from "@/components/AdminSignIn";

type Tab = "overview" | "roster" | "vote" | "matches" | "scores" | "standings" | "audit";
interface CodeStatus { user_id: string; status: string; code_hint: string | null; last_used_at: string | null }

export default function AdminTournament() {
  const { id } = useParams<{ id: string }>();
  const { user, ready } = useAdminSession();
  const { data, error, reload } = useTournament(id);
  const [tab, setTab] = useState<Tab>("overview");
  const [msg, setMsg] = useState<string | null>(null);

  if (!ready) return <p className="muted">Loading...</p>;
  if (!user) return <AdminSignIn />;
  if (error) return <p className="text-red-600">{error}</p>;
  if (!data) return <p className="muted">Loading...</p>;

  const isAdmin = data.tournament.creator_user_id === user.id || data.players.some((p) => p.user_id === user.id && p.is_admin);
  if (!isAdmin) return <p className="text-red-600">You are not an admin of this tournament.</p>;

  const act = async (fn: () => PromiseLike<{ error: { message: string } | null }>) => {
    setMsg(null);
    const { error } = await fn();
    if (error) setMsg(error.message);
    reload();
  };

  const tabs: Tab[] = ["overview", "roster", "vote", "matches", "scores", "standings", "audit"];
  return (
    <div className="space-y-4">
      <Link href="/admin" className="muted underline print:hidden">All tournaments</Link>
      <h1 className="text-2xl font-bold text-brand">{data.tournament.name}</h1>
      <nav className="flex gap-1 overflow-x-auto print:hidden">
        {tabs.map((t) => (
          <button key={t} onClick={() => setTab(t)} className={`${tab === t ? "btn" : "btn-ghost"} !px-3 !py-2 capitalize`}>{t === "vote" ? "Vote & draft" : t}</button>
        ))}
      </nav>
      {msg && <p className="text-sm text-red-600">{msg}</p>}
      {tab === "overview" && <Overview data={data} act={act} />}
      {tab === "roster" && <Roster data={data} reload={reload} setMsg={setMsg} />}
      {tab === "vote" && <VoteDraft data={data} act={act} setMsg={setMsg} reload={reload} />}
      {tab === "matches" && <Matches data={data} act={act} />}
      {tab === "scores" && <Scores data={data} setMsg={setMsg} reload={reload} />}
      {tab === "standings" && <Standings data={data} />}
      {tab === "audit" && <Audit id={id} />}
    </div>
  );
}

type Act = (fn: () => PromiseLike<{ error: { message: string } | null }>) => Promise<void>;

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
  return (
    <div className="space-y-3">
      <div className="card grid grid-cols-3 text-center">
        <div><div className="text-2xl font-bold">{accepted.length}</div><div className="muted">Players</div></div>
        <div><div className="text-2xl font-bold">{t.total_matches}</div><div className="muted">Matches</div></div>
        <div><div className="text-2xl font-bold">{Number(t.points_to_win).toFixed(1)}</div><div className="muted">To win</div></div>
      </div>
      <div className="card">
        <div className="muted">Stage</div>
        <div className="text-xl font-bold capitalize">{t.status}</div>
        {t.status === "setup" && <>
          <p className="muted mt-1">Add players on the Roster tab, then start the captain vote. Needs at least 2 players.</p>
          <button className="btn mt-3 w-full" disabled={accepted.length < 2} onClick={startDraft}>Start captain vote and draft</button></>}
        {t.status === "draft" && <p className="muted mt-1">{voters} of {accepted.length} players have voted. Use Vote and draft to finalize.</p>}
      </div>
      <SpectatorLink id={t.id} />
      <div className="card">
        <h2 className="h2">Courses</h2>
        {data.courses.map((c) => (
          <div key={c.id} className="flex justify-between text-sm"><span>R{c.round_number}: {c.course_name || "TBD"}</span><span className="muted">{c.match_type ? MATCH_LABEL[c.match_type] : ""}</span></div>
        ))}
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

  return (
    <div className="space-y-3">
      {issued.length > 0 && (
        <div className="card">
          <div className="flex items-center justify-between print:hidden">
            <h2 className="h2">New codes (shown once)</h2>
            <span className="flex gap-2">
              <button className="btn-ghost !py-2" onClick={() => downloadText("player-codes.csv", toCsv([["name", "code"], ...issued.map((i) => [i.name, formatCode(i.code)])]))}>Download CSV</button>
              <button className="btn-ghost !py-2" onClick={() => window.print()}>Print cards</button>
            </span>
          </div>
          <p className="muted print:hidden">Codes are stored hashed, so they cannot be shown again. Print or copy them now.</p>
          <div className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2 print:grid-cols-2">
            {issued.map((i) => (
              <div key={i.name} className="rounded-xl border border-dashed border-stone-400 p-3 text-center">
                <div className="muted">{data.tournament.name}</div>
                <div className="font-bold">{i.name}</div>
                <div className="my-1 font-mono text-2xl tracking-widest">{formatCode(i.code)}</div>
                <div className="text-xs text-stone-500">Enter this code at the tournament site</div>
              </div>
            ))}
          </div>
        </div>
      )}
      <div className="card space-y-2 print:hidden">
        <h2 className="h2">Add players</h2>
        <p className="muted">Creates a player account with a login code. One name per line to add several.</p>
        <textarea className="input" rows={3} placeholder={"Jane Smith\nMike Jones"} value={bulk} onChange={(e) => setBulk(e.target.value)} />
        <input className="input" placeholder="Or a single name" value={name} onChange={(e) => setName(e.target.value)} />
        <button className="btn w-full" disabled={busy || locked || !(name.trim() || bulk.trim())}
          onClick={() => create([...bulk.split("\n"), name].map((s) => s.trim()).filter(Boolean))}>
          {busy ? "Creating..." : "Create players and codes"}
        </button>
        {locked && <p className="muted">Roster is locked once the draft starts.</p>}
      </div>
      <div className="space-y-2 print:hidden">
        {data.players.map((p) => {
          const c = codes.find((x) => x.user_id === p.user_id);
          return (
            <div key={p.id} className="card flex items-center justify-between">
              <div>
                <div className="font-semibold">{p.display_name}{p.is_admin && " ★"}</div>
                <div className="muted">{p.invite_status}{c ? ` · code ${c.status}${c.code_hint ? ` (…${c.code_hint})` : ""}${c.last_used_at ? ` · last used ${new Date(c.last_used_at).toLocaleString()}` : " · not used yet"}` : ""}</div>
              </div>
              {c && (
                <div className="flex gap-1">
                  <button className="btn-ghost !px-3 !py-2" onClick={() => regen(p.user_id, p.display_name)}>New code</button>
                  {c.status === "active" && <button className="btn-ghost !px-3 !py-2" onClick={() => revoke(p.user_id)}>Revoke</button>}
                </div>
              )}
            </div>
          );
        })}
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

  const startTournament = () => act(async () => {
    const s = await supabase.from("tournaments").update({ status: "active", updated_at: new Date().toISOString() }).eq("id", t.id);
    if (s.error) return s;
    const rows = Array.from({ length: t.total_matches }, (_, i) => ({
      tournament_id: t.id, matchup_number: i + 1, team_a_id: a.id, team_b_id: b.id,
      match_type: data.courses.find((c) => c.round_number === i + 1)?.match_type ?? t.match_type,
    }));
    return supabase.from("tournament_matchups").insert(rows);
  });

  if (t.status === "setup") return <p className="muted">Start the captain vote from the Overview tab first.</p>;
  const nameOf = (uid: string) => data.players.find((p) => p.user_id === uid)?.display_name ?? uid.slice(0, 6);

  return (
    <div className="space-y-3">
      {!captainsSet && t.status === "draft" && (
        <div className="card">
          <h2 className="h2">Captain vote</h2>
          <p className="muted">{new Set(data.votes.map((v) => v.voter_user_id)).size} of {accepted.length} voted. You always see live counts.</p>
          {tally.map(({ p, n }) => <div key={p.id} className="flex justify-between py-1 text-sm"><span>{p.display_name}</span><b>{n}</b></div>)}
          <button className="btn mt-3 w-full" onClick={() => finalize()}>Finalize captains</button>
        </div>
      )}
      {tie && (
        <div className="card ring-2 ring-amber-400">
          <h2 className="h2">Break the tie</h2>
          <p className="muted">Choose {tie.slots} of these tied nominees.</p>
          {tie.candidates.map((c) => (
            <button key={c} onClick={() => setPick((s) => s.includes(c) ? s.filter((x) => x !== c) : s.length < tie.slots ? [...s, c] : s)}
              className={`mt-1 flex w-full justify-between rounded-xl px-3 py-2 ring-1 ring-stone-300 ${pick.includes(c) ? "bg-brand text-white" : ""}`}>
              {nameOf(c)}{pick.includes(c) && <span>✓</span>}
            </button>
          ))}
          <button className="btn mt-3 w-full" disabled={pick.length !== tie.slots} onClick={() => finalize(pick)}>Confirm</button>
        </div>
      )}
      {captainsSet && (
        <>
          <div className="flex gap-3">
            {[a, b].map((tm) => (
              <div key={tm.id} className="card flex-1">
                <div className="font-bold">{tm.name}</div>
                {accepted.filter((p) => p.team_id === tm.id).map((p) => <div key={p.id} className="text-sm">{p.display_name}{p.user_id === tm.captain_user_id && " (C)"}</div>)}
              </div>
            ))}
          </div>
          {t.status === "draft" && undrafted.length > 0 && (
            <div className="card">
              <h2 className="h2">Override: assign a player</h2>
              <p className="muted">{draftPickCount(accepted, data.teams)} picks made. Use only if a captain is unavailable.</p>
              {undrafted.map((p) => (
                <div key={p.id} className="flex items-center justify-between py-1">
                  <span>{p.display_name}</span>
                  <span className="flex gap-1">
                    {[a, b].map((tm) => <button key={tm.id} className="btn-ghost !px-3 !py-1" onClick={() => act(() => supabase.from("tournament_players").update({ team_id: tm.id }).eq("id", p.id))}>{tm.name}</button>)}
                  </span>
                </div>
              ))}
            </div>
          )}
          {t.status === "draft" && undrafted.length === 0 && <button className="btn w-full" onClick={startTournament}>Start tournament</button>}
        </>
      )}
    </div>
  );
}

function Matches({ data, act }: { data: TournamentData; act: Act }) {
  return (
    <div className="space-y-3">
      {data.matchups.length === 0 && <p className="muted">Matches are created when the tournament starts.</p>}
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
    <div className="flex-1">
      <div className="muted">{data.teams.find((t) => t.id === tid)?.name}</div>
      {pool(tid).map((p) => (
        <button key={p.id} disabled={m.status === "complete"} onClick={() => toggle(sel, set, p.user_id)}
          className={`mt-1 block w-full rounded-lg px-2 py-2 text-left text-sm ring-1 ring-stone-300 ${sel.includes(p.user_id) ? "bg-brand text-white" : ""}`}>{p.display_name}</button>
      ))}
    </div>
  );
  return (
    <div className="card space-y-2">
      <div className="flex justify-between"><b>Match {m.matchup_number} · {MATCH_LABEL[m.match_type]}</b><span className="muted">{m.status}</span></div>
      <div className="flex gap-3">{side(m.team_a_id, a, setA)}{side(m.team_b_id, b, setB)}</div>
      {m.status !== "complete" && (
        <button className="btn w-full" disabled={!valid}
          onClick={() => act(() => supabase.from("tournament_matchups").update({ team_a_player_ids: a, team_b_player_ids: b, status: "active" }).eq("id", m.id))}>
          {m.status === "pending" ? "Confirm pairings" : "Update pairings"}
        </button>
      )}
      {!valid && <p className="muted">Pick the same number of players (1 or 2) on each side.</p>}
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
    const v = prompt(`New score for hole ${hole + 1} (blank to clear)`, String(r.scores[hole] ?? ""));
    if (v === null) return;
    const reason = prompt("Reason for this change (required, saved to the audit log)");
    if (!reason) return;
    const { error } = await supabase.rpc("admin_set_hole_score", { p_round: r.id, p_hole: hole + 1, p_strokes: v === "" ? null : Number(v), p_reason: reason });
    if (error) setMsg(error.message); else load();
  };
  const recompute = async (mid: string) => {
    const { error } = await supabase.rpc("admin_recompute_matchup", { p_matchup: mid });
    if (error) setMsg(error.message); else { setMsg(null); reload(); }
  };

  const exportResults = () => {
    const team = (id: string) => data.teams.find((t) => t.id === id)?.name ?? "";
    downloadText(`${data.tournament.name}-results.csv`, toCsv([
      ["match", "format", "course", "team A", "team B", "points A", "points B", "status"],
      ...data.matchups.map((m) => [m.matchup_number, MATCH_LABEL[m.match_type], data.courses.find((c) => c.round_number === m.matchup_number)?.course_name ?? "",
        team(m.team_a_id), team(m.team_b_id), m.points_team_a, m.points_team_b, m.status]),
    ]));
  };
  const exportCards = () => downloadText(`${data.tournament.name}-scorecards.csv`, toCsv([
    ["match", "player", "status", ...Array.from({ length: 18 }, (_, i) => `H${i + 1}`), "total"],
    ...rounds.map((r) => [data.matchups.find((m) => m.id === r.matchup_id)?.matchup_number ?? "", nameOf(r.user_id), r.status,
      ...r.scores, r.scores.reduce<number>((s, v) => s + (v ?? 0), 0)]),
  ]));

  return (
    <div className="space-y-3">
      <div className="flex gap-2">
        <button className="btn-ghost flex-1" onClick={exportResults}>Export results CSV</button>
        <button className="btn-ghost flex-1" onClick={exportCards}>Export scorecards CSV</button>
      </div>
      {data.matchups.map((m) => (
        <div key={m.id} className="card space-y-2">
          <div className="flex items-center justify-between"><b>Match {m.matchup_number}</b>
            <button className="btn-ghost !px-3 !py-1" onClick={() => recompute(m.id)}>Recompute result</button></div>
          {rounds.filter((r) => r.matchup_id === m.id).map((r) => (
            <div key={r.id}>
              <div className="flex justify-between text-sm"><span className="font-semibold">{nameOf(r.user_id)}</span>
                <span className="muted">{r.status} · {r.scores.reduce<number>((s, v) => s + (v ?? 0), 0)}</span></div>
              <div className="grid grid-cols-9 gap-1 text-center text-xs">
                {r.scores.map((s, i) => <button key={i} onClick={() => edit(r, i)} className="rounded bg-stone-100 py-1"><div className="opacity-50">{i + 1}</div>{s ?? "·"}</button>)}
              </div>
            </div>
          ))}
          {!rounds.some((r) => r.matchup_id === m.id) && <p className="muted">No scorecards started.</p>}
        </div>
      ))}
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
    <div className="card space-y-2">
      <h2 className="h2">Spectator link</h2>
      <p className="muted">A read-only live standings page anyone with the link can open. Turning it off breaks the old link.</p>
      {url && <input className="input font-mono text-xs" readOnly value={url} onFocus={(e) => e.currentTarget.select()} />}
      <div className="flex gap-2">
        <button className="btn-ghost flex-1" onClick={() => set(true)}>{token ? "Show link" : "Enable link"}</button>
        {token && <button className="btn-ghost" onClick={() => set(false)}>Turn off</button>}
      </div>
      {err && <p className="text-sm text-red-600">{err}</p>}
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
  if (err) return <p className="text-sm text-red-600">{err}</p>;
  if (!rows) return <p className="muted">Loading...</p>;
  return (
    <div className="space-y-2">
      <div className="flex justify-between">
        <h2 className="h2">Audit log</h2>
        <button className="btn-ghost !py-1" onClick={() => downloadText(`audit-${id}.csv`, toCsv([["time", "who", "action", "target", "reason"], ...rows.map((r) => [r.created_at, r.actor_name, r.action, r.target_type, r.reason])]))}>Export CSV</button>
      </div>
      {rows.length === 0 && <p className="muted">No admin changes recorded yet.</p>}
      {rows.map((r, i) => (
        <div key={i} className="card text-sm">
          <div className="flex justify-between"><b>{r.action.replace(/_/g, " ")}</b><span className="muted">{new Date(r.created_at).toLocaleString()}</span></div>
          <div className="muted">{r.actor_name ?? "Unknown"}{r.reason ? ` · ${r.reason}` : ""}</div>
          {r.before != null && r.after != null && <div className="mt-1 font-mono text-xs">{JSON.stringify(r.before)}<br />to {JSON.stringify(r.after)}</div>}
        </div>
      ))}
    </div>
  );
}
