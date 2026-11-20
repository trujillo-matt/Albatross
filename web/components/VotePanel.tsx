"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase";
import type { TournamentData } from "@/lib/types";
import { CheckIcon } from "./ui";

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
    <div className="space-y-4">
      <div className="space-y-1">
        <p className="muted">Phase 1</p>
        <h2 className="font-serif text-2xl text-stone-900">Vote for captains</h2>
        <p className="muted">Choose exactly 2 nominees. The top 2 vote-getters become team captains</p>
        <p className="muted"><span className="tnum">{voters}</span> of <span className="tnum">{pool.length}</span> players voted</p>
      </div>
      <div className="card overflow-hidden p-0">
        <ul className="rows">
          {pool.map((p) => {
            const on = sel.includes(p.user_id);
            const count = data.votes.filter((v) => v.nominee_user_id === p.user_id).length;
            return (
              <li key={p.id}>
                <button className="pick" aria-pressed={on} disabled={voted} onClick={() => toggle(p.user_id)}>
                  <span className="text-stone-900">{p.display_name}</span>
                  <span className="flex items-center gap-3 text-brand-accent">
                    {voted && count > 0 && <span className="num text-xl text-stone-900">{count}</span>}
                    {on && <CheckIcon />}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      </div>
      {voted ? (
        <p className="muted text-center">Your vote is in. Counts stay hidden until you vote</p>
      ) : (
        <button className="btn w-full" disabled={sel.length !== 2 || busy} onClick={submit}>Submit votes ({sel.length} of 2)</button>
      )}
      {err && <p role="alert" className="text-sm text-bad">{err}</p>}
    </div>
  );
}
