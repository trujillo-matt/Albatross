"use client";
import { useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";
import { FORMAT } from "@/lib/labels";
import { fillTeeTimes, fromLocalInput, groupTimes, moveToNewTimes, teeTimeFor, toLocalInput } from "@/lib/teams";
import type { TSession, TournamentData } from "@/lib/types";

/** Admin: tee time groups for each session. Set the times, then drag names into the groups. Players with the same time play together. */
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
  // A group is a tee time. Whoever has that time is in the group; nobody can have a time that is not a group.
  const [groups, setGroups] = useState<string[]>(() => [...new Set(players.map((p) => saved(p.user_id)).filter(Boolean))].sort());
  const [first, setFirst] = useState("");
  const [gap, setGap] = useState(10);
  const [perGroup, setPerGroup] = useState(4);
  const [picked, setPicked] = useState<string | null>(null);   // tap a name, then tap a group: the way to do it without a mouse
  const [over, setOver] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const dirty = players.some((p) => (values[p.user_id] ?? "") !== saved(p.user_id));
  const teamName = (id: string | null) => data.teams.find((t) => t.id === id)?.name ?? "No team";
  const unassigned = players.filter((p) => !values[p.user_id]);
  const membersOf = (time: string) => players.filter((p) => values[p.user_id] === time);
  const pickedName = players.find((p) => p.user_id === picked)?.display_name;

  const save = async () => {
    setBusy(true); setMsg(null);
    const times = players.filter((p) => (values[p.user_id] ?? "") !== saved(p.user_id))
      .map((p) => ({ user_id: p.user_id, tee_time: fromLocalInput(values[p.user_id] ?? "") }));
    const { error } = await supabase.rpc("set_tee_times", { p_session: session.id, p_times: times });
    setBusy(false);
    if (error) setMsg(error.message); else reload();
  };

  const place = (uid: string, time: string) => { setValues((v) => ({ ...v, [uid]: time })); setPicked(null); setOver(null); };
  const dropOn = (e: React.DragEvent, time: string) => {
    e.preventDefault();
    const uid = e.dataTransfer.getData("text/plain");
    if (uid && players.some((p) => p.user_id === uid)) place(uid, time);
    setOver(null);
  };
  const allow = (e: React.DragEvent, key: string) => { e.preventDefault(); setOver(key); };

  // New group times: people stay in the group they were in, by position.
  const setTimes = () => {
    const next = groupTimes(first, gap, Math.max(1, Math.ceil(players.length / perGroup)));
    setValues((v) => moveToNewTimes(v, groups, next));
    setGroups(next);
  };
  // Shortcut: fill every group in list order, so each group is a team's players together.
  const autoFill = () => {
    const filled = fillTeeTimes(players.map((p) => p.user_id), first, gap, perGroup);
    setValues((v) => ({ ...v, ...filled }));
    setGroups([...new Set(Object.values(filled))].sort());
  };
  const addGroup = () => {
    const last = groups[groups.length - 1] ?? first;
    if (!last) return;
    setGroups((g) => [...g, groups.length ? groupTimes(last, gap, 2)[1] : last]);
  };
  const retime = (old: string, next: string) => {
    if (!next || next === old) return;
    if (groups.includes(next)) { setMsg("Two groups cannot start at the same time"); return; }
    setMsg(null);
    setGroups((g) => g.map((t) => (t === old ? next : t)).sort());
    setValues((v) => Object.fromEntries(Object.entries(v).map(([uid, t]) => [uid, t === old ? next : t])));
  };

  // A plain function, not a component, so a name is not remounted (which would cancel a drag) each time state changes.
  const nameChip = (uid: string, name: string, sub: string) => (
    <button key={uid} type="button" draggable aria-pressed={picked === uid} onClick={() => setPicked(picked === uid ? null : uid)}
      onDragStart={(e) => { e.dataTransfer.setData("text/plain", uid); e.dataTransfer.effectAllowed = "move"; setPicked(null); }}
      className={`flex w-full cursor-grab items-center justify-between gap-2 rounded-lg px-3 py-2 text-left ring-1 ring-hair active:cursor-grabbing ${picked === uid ? "bg-brand-light ring-2 ring-brand" : "bg-white hover:bg-stone-100"}`}>
      <span className="truncate font-medium text-stone-900">{name}</span>
      <span className="muted shrink-0">{sub}</span>
    </button>
  );

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
        <button className="btn" type="button" disabled={!first} onClick={setTimes}>Set group times</button>
        <button className="btn-ghost" type="button" disabled={!first} onClick={autoFill}>Fill in by team</button>
      </div>

      <div className="grid gap-4 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)] lg:items-start">
        <section aria-label="Players without a group" onDragOver={(e) => allow(e, "pool")} onDragLeave={() => setOver(null)} onDrop={(e) => dropOn(e, "")}
          className={`space-y-2 rounded-xl p-3 ring-1 ring-hair lg:sticky lg:top-4 ${over === "pool" ? "bg-brand-light" : "bg-stone-50"}`}>
          <h3 className="font-medium text-stone-900">Players <span className="muted tnum">({unassigned.length} without a group)</span></h3>
          {unassigned.length === 0 && <p className="muted">Everyone is in a group. Drag a name here to take them out</p>}
          <ul className="space-y-2">
            {unassigned.map((p) => <li key={p.id}>{nameChip(p.user_id, p.display_name, teamName(p.team_id))}</li>)}
          </ul>
          {picked && values[picked] && <button type="button" className="btn-ghost w-full" onClick={() => place(picked, "")}>Take {pickedName} out of their group</button>}
        </section>

        <div className="space-y-3">
          {groups.length === 0 && <p className="muted">Set the first tee time and press Set group times. Then drag names into the groups</p>}
          <div className="grid gap-3 sm:grid-cols-2">
            {groups.map((time, i) => {
              const members = membersOf(time);
              return (
                <section key={time} aria-label={`Group ${i + 1}`} onDragOver={(e) => allow(e, time)} onDragLeave={() => setOver(null)} onDrop={(e) => dropOn(e, time)}
                  className={`space-y-2 rounded-xl p-3 ring-1 ring-hair ${over === time ? "bg-brand-light" : "bg-white"}`}>
                  <div className="flex items-center justify-between gap-2">
                    <h3 className="font-medium text-stone-900">Group <span className="tnum">{i + 1}</span> <span className="muted tnum">({members.length})</span></h3>
                    {members.length === 0 && <button type="button" className="muted underline" onClick={() => setGroups((g) => g.filter((t) => t !== time))}>Remove</button>}
                  </div>
                  <input className="input" type="datetime-local" aria-label={`Tee time for group ${i + 1}`} value={time} onChange={(e) => retime(time, e.target.value)} />
                  <ul className="space-y-2">
                    {members.map((p) => <li key={p.id}>{nameChip(p.user_id, p.display_name, teamName(p.team_id))}</li>)}
                  </ul>
                  {picked && values[picked] !== time && <button type="button" className="btn w-full" onClick={() => place(picked, time)}>Put {pickedName} here</button>}
                </section>
              );
            })}
          </div>
          {first && <button type="button" className="btn-ghost" onClick={addGroup}>Add a group</button>}
        </div>
      </div>

      <button className="btn w-full" disabled={busy || !dirty} onClick={save}>Save tee times</button>
      {msg && <p role="alert" className="text-sm text-bad">{msg}</p>}
    </div>
  );
}
