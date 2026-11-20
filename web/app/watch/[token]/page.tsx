"use client";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { FORMAT } from "@/lib/labels";
import Page from "@/components/Page";
import Scoreboard from "@/components/Scoreboard";
import { MatchupStatusLabel } from "@/components/ui";
import type { MatchType, MatchupStatus } from "@/lib/types";

interface Public {
  name: string; status: string; points_to_win: number;
  teams: { id: string; name: string; side: string; players: string[] }[];
  matchups: { number: number; type: MatchType; status: MatchupStatus; team_a_id: string; team_b_id: string; points_a: number; points_b: number }[];
}

/** Read-only live standings for anyone with the link. No sign in. Polls because anonymous clients cannot use table realtime. */
export default function Watch() {
  const { token } = useParams<{ token: string }>();
  const [d, setD] = useState<Public | null>(null);
  const [state, setState] = useState<"loading" | "ok" | "gone">("loading");

  useEffect(() => {
    let live = true;
    const load = async () => {
      const { data, error } = await supabase.rpc("get_public_standings", { p_token: token });
      if (!live) return;
      if (error || !data) { setState("gone"); return; }
      setD(data as Public); setState("ok");
    };
    load();
    const t = setInterval(load, 15000);
    return () => { live = false; clearInterval(t); };
  }, [token]);

  if (state === "loading") return <Page><p className="muted">Loading</p></Page>;
  if (state === "gone" || !d) return <Page><p className="card">This link is not active. Ask the organizer for a new one</p></Page>;

  const [a, b] = d.teams;
  const pa = d.matchups.reduce((s, m) => s + Number(m.points_a), 0);
  const pb = d.matchups.reduce((s, m) => s + Number(m.points_b), 0);
  const name = (id: string) => d.teams.find((t) => t.id === id)?.name ?? "Team";
  return (
    <Page>
      <div className="space-y-6">
        <h1 className="h1">{d.name}</h1>
        <Scoreboard teams={[a && { name: a.name, points: pa }, b && { name: b.name, points: pb }]} toWin={Number(d.points_to_win)} complete={d.status === "complete"} />
        <div className="card overflow-hidden p-0">
          <ul className="rows">
            {d.matchups.map((m) => (
              <li key={m.number} className="row px-4">
                <div>
                  <div className="text-stone-900">Match <span className="tnum">{m.number}</span></div>
                  <div className="muted">{FORMAT[m.type] ?? m.type}</div>
                </div>
                {m.status === "complete" ? (
                  <div className="text-right">
                    <div className="num text-lg text-stone-900">{Number(m.points_a).toFixed(1)} to {Number(m.points_b).toFixed(1)}</div>
                    <div className="muted">{name(m.team_a_id)} vs {name(m.team_b_id)}</div>
                  </div>
                ) : <MatchupStatusLabel status={m.status} />}
              </li>
            ))}
          </ul>
        </div>
        <div className="grid gap-3 sm:grid-cols-2">
          {d.teams.map((t) => (
            <div key={t.id} className="card"><div className="h2">{t.name}</div><p className="muted mt-1">{t.players.join(", ") || "No players yet"}</p></div>
          ))}
        </div>
        <p className="muted text-center">Updates every 15 seconds</p>
      </div>
    </Page>
  );
}
