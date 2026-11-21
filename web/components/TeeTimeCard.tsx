"use client";
import { groupsForSession, teeTimeFor, teeTimeLabel } from "@/lib/teams";
import { currentSession } from "@/lib/sessions";
import type { TournamentData } from "@/lib/types";

/** What a player sees: their own tee time up front, then everyone's, grouped by time. Hidden until an admin sets some. */
export default function TeeTimeCard({ data, me }: { data: TournamentData; me: string }) {
  const sessions = [...data.sessions].filter((s) => data.teeTimes.some((t) => t.session_id === s.id))
    .sort((a, b) => a.day_number - b.day_number || a.session_number - b.session_number);
  if (sessions.length === 0) return null;
  const now = currentSession(data.sessions);
  const next = sessions.find((s) => s.id === now?.id) ?? sessions[0];
  const mine = teeTimeFor(data.teeTimes, next.id, me);
  return (
    <section className="card space-y-3" aria-label="Tee times">
      <h2 className="h2">Tee times</h2>
      <p className="text-stone-900">
        {mine ? <>Your tee time, Day <span className="tnum">{next.day_number}</span>{next.label ? ` ${next.label}` : ""}: <strong>{teeTimeLabel(mine)}</strong></>
          : <span className="muted">No tee time for you yet in Day {next.day_number}{next.label ? ` ${next.label}` : ""}</span>}
      </p>
      <details>
        <summary className="muted cursor-pointer">Everyone&apos;s tee times</summary>
        <div className="mt-3 space-y-4">
          {sessions.map((s) => (
            <div key={s.id}>
              <div className="text-sm text-stone-900">Day <span className="tnum">{s.day_number}</span>{s.label ? `, ${s.label}` : ""}</div>
              <ul className="rows">
                {groupsForSession(data.teeTimes, s.id, data.players).map((g) => (
                  <li key={g.time} className="row"><span className="tnum text-stone-900">{teeTimeLabel(g.time)}</span><span className="muted min-w-0 truncate">{g.players.map((p) => p.display_name).join(", ")}</span></li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </details>
    </section>
  );
}
