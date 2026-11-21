"use client";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useTournament, useUserId } from "@/lib/useTournament";
import { supabase } from "@/lib/supabase";
import { FORMAT } from "@/lib/labels";
import { orderedTeams } from "@/lib/draft";
import { courseForMatch } from "@/lib/sessions";
import DayBoard from "@/components/DayBoard";
import VotePanel from "@/components/VotePanel";
import DraftPanel from "@/components/DraftPanel";
import Standings from "@/components/Standings";
import Page from "@/components/Page";
import { CaptainBadge, MatchupStatusLabel, TournamentStatusLabel } from "@/components/ui";

export default function PlayerHub() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { userId, ready } = useUserId();
  const { data, error, reload } = useTournament(id);
  const [tab, setTab] = useState<"play" | "standings">("play");

  useEffect(() => { if (ready && !userId) router.replace("/join"); }, [ready, userId, router]);

  if (error) return <Page><p role="alert" className="text-bad">{error}</p></Page>;
  if (!data || !userId) return <Page><p className="muted">Loading</p></Page>;

  const { tournament: t } = data;
  const [teamA, teamB] = orderedTeams(data.teams);
  const captainsSet = !!teamA?.captain_user_id && !!teamB?.captain_user_id;
  const meP = data.players.find((p) => p.user_id === userId);
  const myTeam = data.teams.find((x) => x.id === meP?.team_id);

  return (
    <Page>
      <div className="space-y-6">
        <header className="flex items-start justify-between gap-4">
          <div className="min-w-0 space-y-1">
            <h1 className="h1 truncate">{t.name}</h1>
            <p className="muted flex flex-wrap items-center gap-x-3 gap-y-1">
              <span>{meP && data.teams.some((x) => x.captain_user_id === meP.user_id) && <CaptainBadge />}{meP?.display_name}{myTeam ? `, ${myTeam.name}` : ""}</span>
              <TournamentStatusLabel status={t.status} />
            </p>
          </div>
          <button className="btn-ghost btn-sm shrink-0" onClick={async () => { await supabase.auth.signOut(); router.replace("/join"); }}>Sign out</button>
        </header>

        <nav className="tabs" aria-label="Tournament sections">
          <button className="tab" aria-current={tab === "play" ? "page" : undefined} onClick={() => setTab("play")}>Play</button>
          <button className="tab" aria-current={tab === "standings" ? "page" : undefined} onClick={() => setTab("standings")}>Standings</button>
        </nav>

        {tab === "standings" && <Standings data={data} />}

        {tab === "play" && (
          <>
            {t.status === "setup" && (
              <div className="card space-y-1">
                <h2 className="h2">Waiting for the draft</h2>
                <p className="muted">The organizer will start the captain vote soon. <span className="tnum">{data.players.filter((p) => p.invite_status === "accepted").length}</span> players are in</p>
              </div>
            )}
            {t.status === "draft" && !captainsSet && <VotePanel data={data} me={userId} reload={reload} />}
            {t.status === "draft" && captainsSet && <DraftPanel data={data} me={userId} reload={reload} />}
            {(t.status === "active" || t.status === "complete") && (
              <section className="space-y-3">
                {data.sessions.length > 0 && data.matchups.some((m) => m.session_id) && (
                  <>
                    <h2 className="h2">Today</h2>
                    <DayBoard data={data} userId={userId} isAdmin={false} reload={reload} />
                  </>
                )}
                <h2 className="h2">Matches</h2>
                <div className="card overflow-hidden p-0">
                  <ul className="rows">
                    {data.matchups.map((m) => {
                      const mine = m.team_a_player_ids.includes(userId) || m.team_b_player_ids.includes(userId);
                      return (
                        <li key={m.id}>
                          <Link href={`/t/${id}/match/${m.id}`} className="pick">
                            <span className="min-w-0">
                              <span className="flex items-center gap-2 text-stone-900">Match <span className="tnum">{m.matchup_number}</span>
                                {mine && <span className="rounded bg-brand-light px-2 text-xs leading-5 text-brand">You</span>}</span>
                              <span className="muted block truncate">{FORMAT[m.match_type]}{courseForMatch(data, m).name ? `, ${courseForMatch(data, m).name}` : ""}</span>
                            </span>
                            {m.status === "complete"
                              ? <span className="num text-lg text-stone-900">{Number(m.points_team_a).toFixed(1)} to {Number(m.points_team_b).toFixed(1)}</span>
                              : <MatchupStatusLabel status={m.status} />}
                          </Link>
                        </li>
                      );
                    })}
                  </ul>
                </div>
              </section>
            )}
          </>
        )}
      </div>
    </Page>
  );
}
