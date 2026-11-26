"use client";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { timeAgo } from "@/lib/labels";
import { Dot, type Tone } from "./ui";

interface NewsItem { id: string; tournament_id: string; kind: string; headline: string; created_at: string }

const TONE: Record<string, Tone> = { ace: "live", eagle: "live", birdie: "live", score_change: "warn", match_result: "idle", lead_change: "live" };

/**
 * "Tournament news": birdies and better, changed scores and finished matches and lead changes, newest first.
 * The database writes the entries (migration 010); this reads them and refreshes when a new one arrives.
 */
export default function NewsFeed({ tournamentIds, names }: { tournamentIds: string[]; names?: Record<string, string> }) {
  const [items, setItems] = useState<NewsItem[]>([]);
  const key = tournamentIds.join(",");

  useEffect(() => {
    if (!key) { setItems([]); return; }
    const ids = key.split(",");
    let stopped = false;
    const load = async () => {
      const { data } = await supabase.from("tournament_news").select("id, tournament_id, kind, headline, created_at")
        .in("tournament_id", ids).order("created_at", { ascending: false }).limit(20);
      if (!stopped && data) setItems(data as NewsItem[]);
    };
    load();
    const channel = supabase.channel(`news-${key}`)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "tournament_news" }, load)
      .subscribe();
    return () => { stopped = true; supabase.removeChannel(channel); };
  }, [key]);

  return (
    <section className="card space-y-3" aria-label="Tournament news">
      <h2 className="h2">Tournament news</h2>
      {items.length === 0
        ? <p className="muted">Birdies, changed scores and finished matches show up here</p>
        : (
          <ul className="rows">
            {items.map((n) => (
              <li key={n.id} className="row">
                <div className="min-w-0">
                  <div className="flex items-center gap-2 text-stone-900"><Dot tone={TONE[n.kind] ?? "idle"} />{n.headline}</div>
                  <div className="muted">{names?.[n.tournament_id] ? `${names[n.tournament_id]} · ` : ""}{timeAgo(n.created_at)}</div>
                </div>
              </li>
            ))}
          </ul>
        )}
    </section>
  );
}
