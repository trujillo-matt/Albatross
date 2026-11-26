"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { supabase } from "./supabase";
import type { TournamentData, TPlayer } from "./types";

export function useUserId() {
  const [userId, setUserId] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  useEffect(() => {
    // The saved session, not a call to the server, so the page still knows who you are with no signal. The database checks every write.
    supabase.auth.getSession().then(({ data }) => { setUserId(data.session?.user?.id ?? null); setReady(true); });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setUserId(s?.user?.id ?? null));
    return () => sub.subscription.unsubscribe();
  }, []);
  return { userId, ready };
}

const savedKey = (id: string) => `albatross-tournament:${id}`;
function readSaved(id: string): TournamentData | null {
  try { return JSON.parse(localStorage.getItem(savedKey(id)) ?? "null"); } catch { return null; }
}

/** Loads one tournament with all sub-tables and refreshes on any realtime change. */
export function useTournament(id: string) {
  const [data, setData] = useState<TournamentData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const load = useCallback(async () => {
    const q = (table: string) => supabase.from(table).select("*").eq("tournament_id", id);
    const [t, courses, players, teams, matchups, votes, sessions, teeTimes] = await Promise.all([
      supabase.from("tournaments").select("*").eq("id", id).single(),
      q("tournament_courses").order("round_number"),
      q("tournament_players"),
      q("tournament_teams"),
      q("tournament_matchups").order("matchup_number"),
      q("tournament_captain_votes"),
      q("tournament_sessions").order("day_number").order("session_number"),
      q("tournament_tee_times"),   // migration 013; an older database simply has none
    ]);
    if (t.error) {
      // No signal: show the copy saved the last time this tournament loaded, so scoring can go on and queue.
      const saved = /fetch|network|timeout|load failed/i.test(t.error.message) ? readSaved(id) : null;
      if (saved) { setError(null); setData(saved); return; }
      setError(t.error.message);
      return;
    }
    const rawPlayers = (players.data ?? []) as Omit<TPlayer, "display_name">[];
    const ids = rawPlayers.map((p) => p.user_id);
    const profs = ids.length
      ? await supabase.from("profiles").select("id, display_name").in("id", ids)
      : { data: [] as { id: string; display_name: string }[] };
    const names = new Map((profs.data ?? []).map((p) => [p.id, p.display_name]));
    setError(null);
    const loaded: TournamentData = {
      tournament: t.data,
      courses: courses.data ?? [],
      players: rawPlayers.map((p) => ({ ...p, display_name: names.get(p.user_id) ?? "Player" })),
      teams: teams.data ?? [],
      matchups: matchups.data ?? [],
      votes: votes.data ?? [],
      sessions: sessions.data ?? [],
      teeTimes: teeTimes.data ?? [],
    };
    setData(loaded);
    try { localStorage.setItem(savedKey(id), JSON.stringify(loaded)); } catch { /* storage unavailable */ }
  }, [id]);

  useEffect(() => {
    load();
    const refresh = () => {
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(load, 250);
    };
    const ch = supabase.channel(`tournament-${id}`);
    for (const table of ["tournament_players", "tournament_teams", "tournament_matchups", "tournament_captain_votes", "tournament_sessions", "tournament_tee_times"]) {
      ch.on("postgres_changes", { event: "*", schema: "public", table, filter: `tournament_id=eq.${id}` }, refresh);
    }
    ch.on("postgres_changes", { event: "*", schema: "public", table: "tournaments", filter: `id=eq.${id}` }, refresh);
    ch.subscribe();
    return () => { if (timer.current) clearTimeout(timer.current); supabase.removeChannel(ch); };
  }, [id, load]);

  return { data, error, reload: load };
}
