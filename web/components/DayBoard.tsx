"use client";
import { useState } from "react";
import CalloutBoard from "@/components/CalloutBoard";
import { currentSession, groupByDay, sessionPoints } from "@/lib/sessions";
import type { TournamentData } from "@/lib/types";

/** The tournament by day: tabs for days, then every session of the day with its lineup, callouts and results. */
export default function DayBoard({ data, userId, isAdmin, reload }: { data: TournamentData; userId: string | null; isAdmin: boolean; reload: () => void }) {
  const days = groupByDay(data.sessions, data.matchups);
  const now = currentSession(data.sessions);
  const [picked, setPicked] = useState<number | null>(null);
  const day = days.find((d) => d.day === (picked ?? now?.day_number)) ?? days[0];
  if (!day) return null;
  const dayPts = day.sessions.reduce((t, s) => { const p = sessionPoints(s.matchups); return { a: t.a + p.a, b: t.b + p.b }; }, { a: 0, b: 0 });
  const [ta, tb] = [...data.teams].sort((x, y) => (x.side ?? x.name).localeCompare(y.side ?? y.name));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <nav className="flex gap-6" aria-label="Days">
          {days.map((d) => (
            <button key={d.day} className="tab" aria-current={d.day === day.day ? "page" : undefined} onClick={() => setPicked(d.day)}>Day {d.day}</button>
          ))}
        </nav>
        <p className="muted">{ta?.name} <span className="tnum">{dayPts.a}</span>, {tb?.name} <span className="tnum">{dayPts.b}</span> today</p>
      </div>
      <div className="grid gap-4 lg:grid-cols-2 lg:items-start">
        {day.sessions.map(({ session, matchups }) => (
          <CalloutBoard key={session.id} data={data} session={session} matchups={matchups} userId={userId} isAdmin={isAdmin} reload={reload} />
        ))}
      </div>
    </div>
  );
}
