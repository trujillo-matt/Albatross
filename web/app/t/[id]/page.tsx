"use client";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useTournament, useUserId } from "@/lib/useTournament";
import { supabase } from "@/lib/supabase";
import { MATCH_LABEL } from "@/lib/types";
import { orderedTeams } from "@/lib/draft";
import VotePanel from "@/components/VotePanel";
import DraftPanel from "@/components/DraftPanel";
import Standings from "@/components/Standings";

export default function PlayerHub() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { userId, ready } = useUserId();
  const { data, error, reload } = useTournament(id);
  const [tab, setTab] = useState<"play" | "standings">("play");

  useEffect(() => { if (ready && !userId) router.replace("/join"); }, [ready, userId, router]);

  if (error) return <p className="text-red-600">{error}</p>;
  if (!data || !userId) return <p className="muted">Loading...</p>;

  const { tournament: t } = data;
  const [teamA, teamB] = orderedTeams(data.teams);
  const captainsSet = !!teamA?.captain_user_id && !!teamB?.captain_user_id;
  const meP = data.players.find((p) => p.user_id === userId);
  const myTeam = data.teams.find((x) => x.id === meP?.team_id);
  const courseFor = (n: number) => data.courses.find((c) => c.round_number === n)?.course_name;

  return (
    <div className="space-y-4">
      <header className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-brand">{t.name}</h1>
          <p className="muted">{meP?.display_name}{myTeam ? ` · ${myTeam.name}` : ""} · {t.status}</p>
        </div>
        <button className="muted underline" onClick={async () => { await supabase.auth.signOut(); router.replace("/join"); }}>Sign out</button>
      </header>

      <nav className="grid grid-cols-2 gap-2">
        <button className={tab === "play" ? "btn" : "btn-ghost"} onClick={() => setTab("play")}>Play</button>
        <button className={tab === "standings" ? "btn" : "btn-ghost"} onClick={() => setTab("standings")}>Standings</button>
      </nav>

      {tab === "standings" && <Standings data={data} />}

      {tab === "play" && (
        <>
          {t.status === "setup" && (
            <div className="card"><h2 className="h2">Waiting for the draft</h2>
              <p className="muted">The admin will start the captain vote soon. {data.players.filter((p) => p.invite_status === "accepted").length} players are in.</p></div>
          )}
          {t.status === "draft" && !captainsSet && <VotePanel data={data} me={userId} reload={reload} />}
          {t.status === "draft" && captainsSet && <DraftPanel data={data} me={userId} reload={reload} />}
          {(t.status === "active" || t.status === "complete") && (
            <div className="space-y-2">
              <h2 className="h2">Matches</h2>
              {data.matchups.map((m) => {
                const mine = m.team_a_player_ids.includes(userId) || m.team_b_player_ids.includes(userId);
                return (
                  <Link key={m.id} href={`/t/${id}/match/${m.id}`} className="card flex items-center justify-between">
                    <div>
                      <div className="font-bold">Match {m.matchup_number}{mine && <span className="ml-2 rounded-full bg-brand-light px-2 py-0.5 text-xs">You</span>}</div>
                      <div className="muted">{MATCH_LABEL[m.match_type]}{courseFor(m.matchup_number) ? ` · ${courseFor(m.matchup_number)}` : ""}</div>
                    </div>
                    <span className="muted">{m.status === "complete" ? `${Number(m.points_team_a).toFixed(1)} to ${Number(m.points_team_b).toFixed(1)}` : m.status}</span>
                  </Link>
                );
              })}
            </div>
          )}
        </>
      )}
    </div>
  );
}
