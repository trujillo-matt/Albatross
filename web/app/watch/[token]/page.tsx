"use client";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

interface Public {
  name: string; status: string; points_to_win: number;
  teams: { id: string; name: string; side: string; players: string[] }[];
  matchups: { number: number; type: string; status: string; team_a_id: string; team_b_id: string; points_a: number; points_b: number }[];
}
const LABEL: Record<string, string> = { scramble: "Scramble", best_ball: "Best Ball", match_play: "Match Play", stroke_play: "Stroke Play" };

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

  if (state === "loading") return <p className="muted">Loading...</p>;
  if (state === "gone" || !d) return <p className="card">This link is not active. Ask the organizer for a new one.</p>;

  const [a, b] = d.teams;
  const pa = d.matchups.reduce((s, m) => s + Number(m.points_a), 0);
  const pb = d.matchups.reduce((s, m) => s + Number(m.points_b), 0);
  const name = (id: string) => d.teams.find((t) => t.id === id)?.name ?? "?";
  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-brand">{d.name}</h1>
      {a && b && (
        <div className="card grid grid-cols-3 items-center text-center">
          <div><div className="font-bold">{a.name}</div><div className={`text-5xl font-bold ${pa > pb ? "text-brand-accent" : ""}`}>{pa.toFixed(1)}</div></div>
          <div className="muted">first to<br />{Number(d.points_to_win).toFixed(1)}</div>
          <div><div className="font-bold">{b.name}</div><div className={`text-5xl font-bold ${pb > pa ? "text-brand-accent" : ""}`}>{pb.toFixed(1)}</div></div>
        </div>
      )}
      {d.matchups.map((m) => (
        <div key={m.number} className="card flex items-center justify-between">
          <div><b>Match {m.number}</b><div className="muted">{LABEL[m.type] ?? m.type}</div></div>
          {m.status === "complete"
            ? <b>{name(m.team_a_id)} {Number(m.points_a).toFixed(1)} to {Number(m.points_b).toFixed(1)} {name(m.team_b_id)}</b>
            : <span className="rounded-full bg-stone-100 px-3 py-1 text-xs">{m.status === "active" ? "In progress" : "Pending"}</span>}
        </div>
      ))}
      {d.teams.map((t) => (
        <div key={t.id} className="card"><b>{t.name}</b><div className="muted">{t.players.join(", ") || "No players yet"}</div></div>
      ))}
      <p className="muted text-center">Updates every 15 seconds</p>
    </div>
  );
}
