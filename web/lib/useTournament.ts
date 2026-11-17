"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { supabase } from "./supabase";
import type { TournamentData, TPlayer } from "./types";

export function useUserId() {
  const [userId, setUserId] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => { setUserId(data.user?.id ?? null); setReady(true); });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setUserId(s?.user?.id ?? null));
    return () => sub.subscription.unsubscribe();
  }, []);
  return { userId, ready };
}

/** Loads one tournament with all sub-tables and refreshes on any realtime change. */
export function useTournament(id: string) {
  const [data, setData] = useState<TournamentData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const load = useCallback(async () => {
    const q = (table: string) => supabase.from(table).select("*").eq("tournament_id", id);
    const [t, courses, players, teams, matchups, votes] = await Promise.all([
      supabase.from("tournaments").select("*").eq("id", id).single(),
      q("tournament_courses").order("round_number"),
      q("tournament_players"),
      q("tournament_teams"),
      q("tournament_matchups").order("matchup_number"),
      q("tournament_captain_votes"),
    ]);
    if (t.error) { setError(t.error.message); return; }
    const rawPlayers = (players.data ?? []) as Omit<TPlayer, "display_name">[];
    const ids = rawPlayers.map((p) => p.user_id);
    const profs = ids.length
      ? await supabase.from("profiles").select("id, display_name").in("id", ids)
      : { data: [] as { id: string; display_name: string }[] };
    const names = new Map((profs.data ?? []).map((p) => [p.id, p.display_name]));
    setError(null);
    setData({
      tournament: t.data,
      courses: courses.data ?? [],
      players: rawPlayers.map((p) => ({ ...p, display_name: names.get(p.user_id) ?? "Player" })),
      teams: teams.data ?? [],
      matchups: matchups.data ?? [],
      votes: votes.data ?? [],
    });
  }, [id]);

  useEffect(() => {
    load();
    const refresh = () => {
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(load, 250);
    };
    const ch = supabase.channel(`tournament-${id}`);
    for (const table of ["tournament_players", "tournament_teams", "tournament_matchups", "tournament_captain_votes"]) {
      ch.on("postgres_changes", { event: "*", schema: "public", table, filter: `tournament_id=eq.${id}` }, refresh);
    }
    ch.on("postgres_changes", { event: "*", schema: "public", table: "tournaments", filter: `id=eq.${id}` }, refresh);
    ch.subscribe();
    return () => { if (timer.current) clearTimeout(timer.current); supabase.removeChannel(ch); };
  }, [id, load]);

  return { data, error, reload: load };
}
