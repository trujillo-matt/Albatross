"use client";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { orderedTeams } from "@/lib/draft";
import { FORMAT, SESSION_STATUS } from "@/lib/labels";
import { calloutState, isLocked, sameUnit, sideOf, sitOuts, unitOf } from "@/lib/sessions";
import type { TMatchup, TSession, TournamentData } from "@/lib/types";
import { CaptainBadge, Status, type Tone } from "@/components/ui";

interface Props {
  data: TournamentData;
  session: TSession;
  matchups: TMatchup[];
  userId: string | null;
  isAdmin: boolean;
  reload: () => void;
}

const TONE: Record<TSession["status"], Tone> = { pending: "idle", lineup: "warn", callouts: "live", locked: "live", complete: "idle" };

/**
 * One session: the auto-filled lineup, then the captains' callouts, then the locked matches.
 * Every rule lives in the database (migration 008); this only shows state and sends the captain's choice.
 */
export default function CalloutBoard({ data, session, matchups, userId, isAdmin, reload }: Props) {
  const [ta, tb] = orderedTeams(data.teams);
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [mine, setMine] = useState<string[] | null>(null);
  const [theirs, setTheirs] = useState<string[] | null>(null);
  const [picked, setPicked] = useState<{ team: string; uid: string } | null>(null);

  const name = (uid: string) => data.players.find((p) => p.user_id === uid)?.display_name ?? "Player";
  const teamName = (id: string | null) => data.teams.find((t) => t.id === id)?.name ?? "";
  const unitName = (u: string[]) => u.map(name).join(" & ");
  const captainOf = (id: string | null) => !!userId && data.teams.find((t) => t.id === id)?.captain_user_id === userId;

  // Both captains have to be on this page for a pick to go live. Each screen checks in every few seconds and the
  // database refuses a pick unless both checked in recently (migration 011).
  const [here, setHere] = useState<Record<string, boolean>>({});
  const watching = session.status === "callouts" && (isAdmin || captainOf(ta?.id ?? null) || captainOf(tb?.id ?? null));
  useEffect(() => {
    if (!watching) return;
    let stopped = false;
    const beat = async () => {
      const { data: rows } = await supabase.rpc("callout_checkin", { p_session: session.id });
      if (!stopped && rows) setHere(Object.fromEntries((rows as { team_id: string; present: boolean }[]).map((r) => [r.team_id, r.present])));
    };
    beat();
    const timer = setInterval(beat, 5000);
    const onVisible = () => { if (document.visibilityState === "visible") beat(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => { stopped = true; clearInterval(timer); document.removeEventListener("visibilitychange", onVisible); };
  }, [watching, session.id]);
  const absent = [ta, tb].filter((t): t is NonNullable<typeof t> => !!t && !here[t.id]);
  const bothHere = !!ta && !!tb && absent.length === 0;

  const state = calloutState(session, matchups);
  const turnIsMine = captainOf(state.turnTeamId);
  const canCall = session.status === "callouts" && (turnIsMine || isAdmin);
  // A captain's own pick needs both captains here. An admin acting for them is not held up.
  const heldUp = turnIsMine && !bothHere;
  const turnSide = sideOf(data.teams, state.turnTeamId);
  const canEdit = (teamId: string) => isAdmin || captainOf(teamId);
  const canManage = isAdmin || captainOf(ta?.id ?? null) || captainOf(tb?.id ?? null);

  const run = async (fn: () => PromiseLike<{ error: { message: string } | null }>) => {
    setBusy(true); setMsg(null);
    const { error } = await fn();
    setBusy(false);
    if (error) setMsg(error.message);
    else { setMine(null); setTheirs(null); setPicked(null); reload(); }
  };

  // Lineup: tap two players on the same team to swap them (a sit-out can swap in for a starter).
  const tapPlayer = (team: string, uid: string) => {
    if (!picked || picked.team !== team) { setPicked({ team, uid }); return; }
    if (picked.uid === uid) { setPicked(null); return; }
    const side = sideOf(data.teams, team);
    if (!side) return;
    const units = matchups.map((m) => unitOf(m, side).map((id) => (id === picked.uid ? uid : id === uid ? picked.uid : id)));
    run(() => supabase.rpc("set_session_side", { p_session: session.id, p_team: team, p_units: units }));
  };

  const chip = (team: string, uid: string) => (
    <button key={uid} className="pick py-2 text-sm" aria-pressed={picked?.uid === uid} disabled={busy || !canEdit(team)} onClick={() => tapPlayer(team, uid)}>
      <span className="flex min-w-0 items-center">{data.teams.some((t) => t.captain_user_id === uid) && <CaptainBadge />}<span className="truncate">{name(uid)}</span></span>
    </button>
  );

  // Callouts: a unit on the caller's side is "mine"; a unit on the other side is the opponent I am asking for.
  const tapUnit = (m: TMatchup, side: "A" | "B") => {
    if (!canCall || isLocked(m)) return;
    const u = unitOf(m, side);
    if (side === turnSide) setMine(sameUnit(mine ?? [], u) ? null : u);
    else setTheirs(sameUnit(theirs ?? [], u) ? null : u);
  };
  const selected = (side: "A" | "B", u: string[]) => sameUnit((side === turnSide ? mine : theirs) ?? [], u);

  const rows = matchups.map((m) => {
    const locked = isLocked(m);
    const cell = (side: "A" | "B", teamId: string) => {
      const u = unitOf(m, side);
      if (session.status === "lineup") {
        return <ul className="divide-y divide-hair overflow-hidden rounded-lg ring-1 ring-hair">{u.map((id) => <li key={id}>{chip(teamId, id)}</li>)}</ul>;
      }
      const interactive = canCall && !locked;
      return (
        <button className="pick py-2 text-sm" aria-pressed={selected(side, u)} disabled={!interactive || busy} onClick={() => tapUnit(m, side)}>
          <span className="min-w-0 break-words">{unitName(u) || "TBD"}</span>
        </button>
      );
    };
    return (
      <li key={m.id} className="space-y-2 py-3">
        <div className="flex items-center justify-between gap-3 text-sm">
          <span className="muted">Match <span className="tnum">{m.matchup_number}</span></span>
          <span className="muted">
            {m.status === "complete" ? <span className="tnum">{m.points_team_a} to {m.points_team_b}</span>
              : locked ? (m.called_by_team_id ? `Locked, called by ${teamName(m.called_by_team_id)}` : "Locked") : session.status === "callouts" ? "Open" : ""}
          </span>
        </div>
        <div className="grid grid-cols-[minmax(0,1fr)_2rem_minmax(0,1fr)] items-center">
          {cell("A", m.team_a_id)}<span className="muted text-center text-xs">vs</span>{cell("B", m.team_b_id)}
        </div>
      </li>
    );
  });

  const ready = !!mine && !!theirs;

  return (
    <div className="card space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h3 className="h2">{session.label || `Session ${session.session_number}`}, {FORMAT[session.match_type]}</h3>
          <p className="muted">{session.course_name || "Course to be set"} · <span className="tnum">{session.match_count}</span> matches</p>
        </div>
        <Status tone={TONE[session.status]}>{SESSION_STATUS[session.status]}</Status>
      </div>

      {session.status === "callouts" && (
        <div role="status" className="rounded-lg bg-stone-50 p-3 text-sm ring-1 ring-hair">
          <strong>{teamName(state.turnTeamId)}</strong> to call
          {turnIsMine ? ". Pick one of your units, then the opponent you want"
            : canCall ? ". You are acting as admin"
            : ". Waiting for their captain"}
          <span className="muted block">
            {bothHere ? "Both captains are here" : `Waiting for the ${absent.map((t) => t.name).join(" and ")} captain to join this page`}
          </span>
          <span className="muted block">
            <span className="tnum">{state.openMatches}</span> open, <span className="tnum">{state.lockedMatches}</span> locked
            {state.nextPassLocks && ". A pass now locks the rest as they stand"}
          </span>
        </div>
      )}

      {session.status === "pending" ? <p className="muted">The lineup is made when the previous session finishes</p> : <ul className="rows">{rows}</ul>}

      {session.status === "lineup" && (
        <div className="grid gap-3 sm:grid-cols-2">
          {[ta, tb].filter(Boolean).map((t) => {
            const out = sitOuts(t!, data.players, matchups, sideOf(data.teams, t!.id)!);
            return (
              <div key={t!.id}>
                <div className="muted mb-2">{t!.name} sitting out</div>
                {out.length === 0 ? <p className="muted text-sm">Everyone plays</p>
                  : <ul className="divide-y divide-hair overflow-hidden rounded-lg ring-1 ring-hair">{out.map((p) => <li key={p.user_id}>{chip(t!.id, p.user_id)}</li>)}</ul>}
              </div>
            );
          })}
        </div>
      )}

      {session.status === "lineup" && canManage && (
        <div className="flex flex-wrap gap-2">
          <button className="btn-ghost" disabled={busy} onClick={() => run(() => supabase.rpc("autofill_session", { p_session: session.id }))}>Re-autofill</button>
          <button className="btn flex-1" disabled={busy} onClick={() => run(() => supabase.rpc("open_callouts", { p_session: session.id }))}>Open callouts</button>
        </div>
      )}
      {session.status === "lineup" && <p className="muted text-sm">Tap two players on the same team to swap them. Callouts start when a captain opens them</p>}

      {canCall && (
        <div className="space-y-2">
          {heldUp && <p className="muted text-sm">Picks go live once both captains are on this page</p>}
          {ready && <p className="text-sm">Call out <strong>{unitName(mine!)}</strong> against <strong>{unitName(theirs!)}</strong></p>}
          <div className="flex gap-2">
            <button className="btn flex-1" disabled={!ready || busy || heldUp}
              onClick={() => run(() => supabase.rpc("make_callout", { p_session: session.id, p_my_unit: mine, p_their_unit: theirs, p_override: !turnIsMine }))}>
              Call it out
            </button>
            <button className="btn-ghost" disabled={busy || heldUp} onClick={() => run(() => supabase.rpc("pass_callout", { p_session: session.id, p_override: !turnIsMine }))}>Pass</button>
          </div>
        </div>
      )}
      {msg && <p role="alert" className="text-sm text-bad">{msg}</p>}
    </div>
  );
}
