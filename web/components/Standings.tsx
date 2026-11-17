"use client";
import { MATCH_LABEL, type TournamentData } from "@/lib/types";
import { orderedTeams } from "@/lib/draft";

export default function Standings({ data }: { data: TournamentData }) {
  const [a, b] = orderedTeams(data.teams);
  const pa = data.matchups.reduce((s, m) => s + Number(m.points_team_a), 0);
  const pb = data.matchups.reduce((s, m) => s + Number(m.points_team_b), 0);
  const name = (id: string) => data.teams.find((t) => t.id === id)?.name ?? "?";
  return (
    <div className="space-y-3">
      {a && b && (
        <div className="card text-center">
          <div className="grid grid-cols-3 items-center">
            <div><div className="font-bold">{a.name}</div><div className={`text-5xl font-bold ${pa > pb ? "text-brand-accent" : ""}`}>{pa.toFixed(1)}</div></div>
            <div className="muted">vs<br />first to {Number(data.tournament.points_to_win).toFixed(1)}</div>
            <div><div className="font-bold">{b.name}</div><div className={`text-5xl font-bold ${pb > pa ? "text-brand-accent" : ""}`}>{pb.toFixed(1)}</div></div>
          </div>
        </div>
      )}
      {data.matchups.map((m) => (
        <div key={m.id} className="card flex items-center justify-between">
          <div>
            <div className="font-bold">Match {m.matchup_number}</div>
            <div className="muted">{MATCH_LABEL[m.match_type]}</div>
          </div>
          {m.status === "complete" ? (
            <div className="text-right font-bold">{name(m.team_a_id)} {Number(m.points_team_a).toFixed(1)} to {Number(m.points_team_b).toFixed(1)} {name(m.team_b_id)}</div>
          ) : (
            <span className="rounded-full bg-stone-100 px-3 py-1 text-xs">{m.status === "active" ? "In progress" : "Pending"}</span>
          )}
        </div>
      ))}
    </div>
  );
}
