"use client";
import { type TournamentData } from "@/lib/types";
import { FORMAT } from "@/lib/labels";
import { orderedTeams } from "@/lib/draft";
import { renderStandingsImage, shareOrDownload } from "@/lib/shareImage";
import Scoreboard from "./Scoreboard";
import { MatchupStatusLabel } from "./ui";

export default function Standings({ data }: { data: TournamentData }) {
  const [a, b] = orderedTeams(data.teams);
  const pa = data.matchups.reduce((s, m) => s + Number(m.points_team_a), 0);
  const pb = data.matchups.reduce((s, m) => s + Number(m.points_team_b), 0);
  const name = (id: string) => data.teams.find((t) => t.id === id)?.name ?? "Team";
  return (
    <div className="space-y-4">
      <Scoreboard
        teams={[a && { name: a.name, points: pa }, b && { name: b.name, points: pb }]}
        toWin={Number(data.tournament.points_to_win)}
        complete={data.tournament.status === "complete"}
      />
      <div className="card overflow-hidden p-0">
        <ul className="rows">
          {data.matchups.map((m) => (
            <li key={m.id} className="row px-4">
              <div>
                <div className="text-stone-900">Match <span className="tnum">{m.matchup_number}</span></div>
                <div className="muted">{FORMAT[m.match_type]}</div>
              </div>
              {m.status === "complete" ? (
                <div className="text-right">
                  <div className="num text-lg text-stone-900">{Number(m.points_team_a).toFixed(1)} to {Number(m.points_team_b).toFixed(1)}</div>
                  <div className="muted">{name(m.team_a_id)} vs {name(m.team_b_id)}</div>
                </div>
              ) : <MatchupStatusLabel status={m.status} />}
            </li>
          ))}
          {data.matchups.length === 0 && <li className="row px-4"><span className="muted">Matches appear when the tournament starts</span></li>}
        </ul>
      </div>
      <button className="btn-ghost w-full" onClick={async () => {
        try { await shareOrDownload(await renderStandingsImage(data), "standings.png"); } catch { /* user cancelled share */ }
      }}>Share standings image</button>
    </div>
  );
}
