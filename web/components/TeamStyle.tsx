"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase";
import { orderedTeams } from "@/lib/draft";
import { TEAM_COLOR_PRESETS, teamColor, textOn } from "@/lib/teams";
import type { TTeam, TournamentData } from "@/lib/types";

/** Name and colour for each team. The captain of a team or any admin can change them. */
export default function TeamStyle({ data, reload }: { data: TournamentData; reload: () => void }) {
  const teams = orderedTeams(data.teams).filter((t): t is TTeam => !!t);
  if (teams.length === 0) return <p className="muted">Teams appear when the captain vote starts</p>;
  return (
    <div className="grid gap-4 md:grid-cols-2 md:items-start">
      {teams.map((t, i) => <TeamCard key={`${t.id}:${t.name}:${t.color}`} team={t} fallback={i === 0 ? "A" : "B"} reload={reload} />)}
    </div>
  );
}

function TeamCard({ team, fallback, reload }: { team: TTeam; fallback: "A" | "B"; reload: () => void }) {
  const [name, setName] = useState(team.name);
  const [color, setColor] = useState<string | null>(team.color ?? null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const shown = color ?? teamColor({ color: null, side: team.side }, fallback);
  const changed = name.trim() !== team.name || (color ?? null) !== (team.color ?? null);

  const save = async () => {
    setBusy(true); setMsg(null);
    const { error } = await supabase.rpc("set_team_style", { p_team: team.id, p_name: name.trim(), p_color: color });
    setBusy(false);
    if (error) setMsg(error.message); else reload();
  };

  return (
    <div className="card space-y-4">
      <div className="flex items-center gap-3">
        <span className="inline-flex h-10 min-w-10 items-center justify-center rounded-lg px-3 text-sm font-medium" style={{ backgroundColor: shown, color: textOn(shown) }}>{name.trim() || "Team"}</span>
        <span className="muted">{team.side === "B" ? "Team B" : "Team A"}</span>
      </div>
      <label className="label block">Team name
        <input className="input mt-1" value={name} maxLength={30} onChange={(e) => setName(e.target.value)} />
      </label>
      <div>
        <div className="label">Colour</div>
        <div className="mt-2 flex flex-wrap items-center gap-2" role="group" aria-label={`Colour for ${team.name}`}>
          {TEAM_COLOR_PRESETS.map((c) => (
            <button key={c} type="button" aria-label={c} aria-pressed={shown.toLowerCase() === c.toLowerCase()} onClick={() => setColor(c)}
              className="h-8 w-8 rounded-full ring-1 ring-black/10 transition-transform duration-150 ease-out active:scale-95 aria-pressed:ring-2 aria-pressed:ring-stone-900 aria-pressed:ring-offset-2"
              style={{ backgroundColor: c }} />
          ))}
          <input type="color" aria-label="Pick another colour" value={shown} onChange={(e) => setColor(e.target.value.toUpperCase())} className="h-8 w-10 cursor-pointer rounded border-0 bg-transparent p-0" />
          {color && <button type="button" className="btn-ghost btn-sm" onClick={() => setColor(null)}>Use the default</button>}
        </div>
      </div>
      <button className="btn w-full" disabled={busy || !changed || !name.trim()} onClick={save}>Save team</button>
      {msg && <p role="alert" className="text-sm text-bad">{msg}</p>}
    </div>
  );
}
