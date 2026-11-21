"use client";
import { useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";
import { FORMAT } from "@/lib/labels";
import { fillTeeTimes, fromLocalInput, teeTimeFor, toLocalInput } from "@/lib/teams";
import type { TSession, TournamentData } from "@/lib/types";

/** Admin: a tee time for each player, one session at a time. Players with the same time play together. */
export default function TeeTimesPanel({ data, reload }: { data: TournamentData; reload: () => void }) {
  const sessions = [...data.sessions].sort((a, b) => a.day_number - b.day_number || a.session_number - b.session_number);
  if (sessions.length === 0) return <p className="muted">Tee times can be set once the tournament has sessions</p>;
  return <div className="space-y-4">{sessions.map((s) => <SessionTimes key={s.id} session={s} data={data} reload={reload} />)}</div>;
}

function SessionTimes({ session, data, reload }: { session: TSession; data: TournamentData; reload: () => void }) {
  const players = useMemo(() => {
    const team = (id: string | null) => data.teams.find((t) => t.id === id)?.name ?? "";
    return data.players.filter((p) => p.invite_status === "accepted")
      .sort((a, b) => team(a.team_id).localeCompare(team(b.team_id)) || a.display_name.localeCompare(b.display_name));
  }, [data.players, data.teams]);
  const saved = (uid: string) => toLocalInput(teeTimeFor(data.teeTimes, session.id, uid));
  const [values, setValues] = useState<Record<string, string>>(() => Object.fromEntries(players.map((p) => [p.user_id, saved(p.user_id)])));
  const [first, setFirst] = useState("");
  const [gap, setGap] = useState(10);
  const [perGroup, setPerGroup] = useState(4);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const dirty = players.some((p) => (values[p.user_id] ?? "") !== saved(p.user_id));
  const teamName = (id: string | null) => data.teams.find((t) => t.id === id)?.name ?? "No team";

  const save = async () => {
    setBusy(true); setMsg(null);
    const times = players.filter((p) => (values[p.user_id] ?? "") !== saved(p.user_id))
      .map((p) => ({ user_id: p.user_id, tee_time: fromLocalInput(values[p.user_id] ?? "") }));
    const { error } = await supabase.rpc("set_tee_times", { p_session: session.id, p_times: times });
    setBusy(false);
    if (error) setMsg(error.message); else reload();
  };

  // Fill in order, so each group is a team's players together: the order of the list below.
  const fill = () => setValues((v) => ({ ...v, ...fillTeeTimes(players.map((p) => p.user_id), first, gap, perGroup) }));

  return (
    <div className="card space-y-4">
      <div>
        <h2 className="h2">Day <span className="tnum">{session.day_number}</span>, {session.label || `Session ${session.session_number}`}</h2>
        <p className="muted">{session.course_name || "Course to be set"} · {FORMAT[session.match_type]}</p>
      </div>
      <div className="flex flex-wrap items-end gap-3">
        <label className="label block">First tee time
          <input className="input mt-1" type="datetime-local" value={first} onChange={(e) => setFirst(e.target.value)} />
        </label>
        <label className="label block">Minutes apart
          <input className="input mt-1 w-24" type="number" min={1} max={60} value={gap} onChange={(e) => setGap(Math.max(1, Number(e.target.value) || 1))} />
        </label>
        <label className="label block">Players per group
          <input className="input mt-1 w-24" type="number" min={1} max={8} value={perGroup} onChange={(e) => setPerGroup(Math.max(1, Number(e.target.value) || 1))} />
        </label>
        <button className="btn-ghost" type="button" disabled={!first} onClick={fill}>Fill in</button>
      </div>
      <ul className="rows">
        {players.map((p) => (
          <li key={p.id} className="row">
            <div className="min-w-0">
              <div className="truncate text-stone-900">{p.display_name}</div>
              <div className="muted">{teamName(p.team_id)}</div>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <input className="input" type="datetime-local" aria-label={`Tee time for ${p.display_name}`} value={values[p.user_id] ?? ""}
                onChange={(e) => setValues((v) => ({ ...v, [p.user_id]: e.target.value }))} />
              {(values[p.user_id] ?? "") !== "" && <button className="btn-ghost btn-sm" type="button" onClick={() => setValues((v) => ({ ...v, [p.user_id]: "" }))}>Clear</button>}
            </div>
          </li>
        ))}
      </ul>
      <button className="btn w-full" disabled={busy || !dirty} onClick={save}>Save tee times</button>
      {msg && <p role="alert" className="text-sm text-bad">{msg}</p>}
    </div>
  );
}
