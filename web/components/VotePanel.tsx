"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase";
import type { TournamentData } from "@/lib/types";

export default function VotePanel({ data, me, reload }: { data: TournamentData; me: string; reload: () => void }) {
  const pool = data.players.filter((p) => p.invite_status === "accepted");
  const voted = data.votes.some((v) => v.voter_user_id === me);
  const voters = new Set(data.votes.map((v) => v.voter_user_id)).size;
  const [sel, setSel] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const toggle = (id: string) =>
    setSel((s) => (s.includes(id) ? s.filter((x) => x !== id) : s.length < 2 ? [...s, id] : s));

  const submit = async () => {
    setBusy(true); setErr(null);
    const { error } = await supabase.rpc("cast_captain_votes", { p_tournament: data.tournament.id, p_nominees: sel });
    if (error) setErr(error.message);
    setBusy(false); reload();
  };

  return (
    <div className="space-y-3">
      <div className="card">
        <div className="muted">Phase 1</div>
        <h2 className="h2">Vote for captains</h2>
        <p className="muted">Choose exactly 2 nominees. The top 2 vote-getters become team captains.</p>
        <p className="muted mt-2">{voters} of {pool.length} players voted</p>
      </div>
      {pool.map((p) => {
        const on = sel.includes(p.user_id);
        const count = data.votes.filter((v) => v.nominee_user_id === p.user_id).length;
        return (
          <button key={p.id} disabled={voted} onClick={() => toggle(p.user_id)}
            className={`card flex w-full items-center justify-between text-left ${on ? "ring-2 ring-brand-accent" : ""}`}>
            <span className="font-semibold">{p.display_name}</span>
            <span className="flex items-center gap-2">
              {voted && count > 0 && <span className="font-bold text-brand-accent">{count}</span>}
              {on && <span>✓</span>}
            </span>
          </button>
        );
      })}
      {voted ? (
        <p className="muted text-center">Your vote has been submitted. Counts are hidden until you vote.</p>
      ) : (
        <button className="btn w-full" disabled={sel.length !== 2 || busy} onClick={submit}>Submit votes ({sel.length}/2)</button>
      )}
      {err && <p className="text-sm text-red-600">{err}</p>}
    </div>
  );
}
