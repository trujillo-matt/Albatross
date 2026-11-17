"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase";
import { draftPickCount, orderedTeams, snakeIsTeamATurn } from "@/lib/draft";
import type { TournamentData } from "@/lib/types";

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
    <div className={`card flex-1 ${isClock ? "ring-2 ring-green-500" : ""}`}>
      <div className="font-bold">{t?.name}{isClock && " ●"}</div>
      <div className="mt-2 space-y-1 text-sm">
        {accepted.filter((p) => p.team_id === t?.id).map((p) => (
          <div key={p.id}>{p.display_name}{p.user_id === t?.captain_user_id && <span className="muted"> (C)</span>}</div>
        ))}
      </div>
    </div>
  );

  return (
    <div className="space-y-3">
      <div className="card">
        <div className="muted">Phase 2</div>
        <h2 className="h2">Snake draft</h2>
        <p className="muted">{undrafted.length === 0 ? "All players drafted." : `${onClock?.name} is on the clock.`}</p>
      </div>
      <div className="flex gap-3">{col(a, aTurn && undrafted.length > 0)}{col(b, !aTurn && undrafted.length > 0)}</div>
      {iAmOnClock && undrafted.length > 0 && (
        <div className="space-y-2">
          <h3 className="h2">Your pick</h3>
          {undrafted.map((p) => (
            <button key={p.id} className="card flex w-full justify-between text-left" onClick={() => pick(p.user_id)}>
              <span className="font-semibold">{p.display_name}</span><span>+</span>
            </button>
          ))}
        </div>
      )}
      {err && <p className="text-sm text-red-600">{err}</p>}
    </div>
  );
}
