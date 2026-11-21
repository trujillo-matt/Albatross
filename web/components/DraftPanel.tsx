"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase";
import { draftPickCount, orderedTeams, snakeIsTeamATurn } from "@/lib/draft";
import type { TournamentData } from "@/lib/types";
import { CaptainBadge, Dot, TeamDot } from "./ui";
import { teamColor } from "@/lib/teams";

export default function DraftPanel({ data, me, reload }: { data: TournamentData; me: string; reload: () => void }) {
  const [a, b] = orderedTeams(data.teams);
  const accepted = data.players.filter((p) => p.invite_status === "accepted");
  const undrafted = accepted.filter((p) => !p.team_id);
  const picks = draftPickCount(accepted, data.teams);
  const aTurn = snakeIsTeamATurn(picks);
  const onClock = aTurn ? a : b;
  const iAmOnClock = !!onClock && onClock.captain_user_id === me;
  const [err, setErr] = useState<string | null>(null);

  const pick = async (userId: string) => {
    setErr(null);
    const { error } = await supabase.rpc("draft_pick", { p_tournament: data.tournament.id, p_player: userId });
    if (error) setErr(error.message);
    reload();
  };

  const col = (t: typeof a, isClock: boolean) => (
    <div className="card flex-1">
      <div className="flex items-center justify-between gap-2">
        <span className="h2">{t && <TeamDot color={teamColor(t)} />}{t?.name}</span>
        {isClock && <span className="inline-flex items-center gap-2 text-xs text-stone-600"><Dot tone="live" />On the clock</span>}
      </div>
      <ul className="mt-3 space-y-1 text-sm text-stone-700">
        {accepted.filter((p) => p.team_id === t?.id).map((p) => (
          <li key={p.id}>{p.user_id === t?.captain_user_id && <CaptainBadge />}{p.display_name}</li>
        ))}
      </ul>
    </div>
  );

  return (
    <div className="space-y-4">
      <div className="space-y-1">
        <p className="muted">Phase 2</p>
        <h2 className="font-serif text-2xl text-stone-900">Snake draft</h2>
        <p className="muted">{undrafted.length === 0 ? "All players are drafted" : `${onClock?.name} is on the clock`}</p>
      </div>
      <div className="flex gap-3">{col(a, aTurn && undrafted.length > 0)}{col(b, !aTurn && undrafted.length > 0)}</div>
      {iAmOnClock && undrafted.length > 0 && (
        <div className="space-y-2">
          <h3 className="h2">Your pick</h3>
          <div className="card overflow-hidden p-0">
            <ul className="rows">
              {undrafted.map((p) => (
                <li key={p.id}><button className="pick" onClick={() => pick(p.user_id)}>
                  <span className="text-stone-900">{p.display_name}</span><span className="text-sm text-brand-accent">Draft</span>
                </button></li>
              ))}
            </ul>
          </div>
        </div>
      )}
      {err && <p role="alert" className="text-sm text-bad">{err}</p>}
    </div>
  );
}
