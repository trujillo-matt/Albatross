// The words of a news alert. Mirrors NewsStoryWriter in the iOS app (Albatross/Helpers/NewsStory.swift), minus the live
// standing, so the alert and the feed read the same way.
export interface NewsRow { id: string; tournament_id: string; matchup_id: string | null; kind: string; player_user_id: string | null; hole: number | null; headline: string }
export interface Matchup { matchup_number: number; team_a_id: string; team_b_id: string; team_a_player_ids: string[]; team_b_player_ids: string[]; result: string | null }
export interface Lookup {
  tournamentName: string;
  matchup: Matchup | null;
  names: Record<string, string>;            // user id -> display name
  teamOf: Record<string, string>;           // user id -> team name
  teamNames: Record<string, string>;        // team id -> name
}

export const ordinal = (n: number): string => {
  const tens = n % 100;
  if (tens >= 11 && tens <= 13) return `${n}th`;
  return `${n}${({ 1: "st", 2: "nd", 3: "rd" } as Record<number, string>)[n % 10] ?? "th"}`;
};
const list = (items: string[]) => new Intl.ListFormat("en", { style: "long", type: "conjunction" }).format(items);

export function writeStory(row: NewsRow, look: Lookup): { title: string; body: string } {
  const m = look.matchup;
  const name = row.player_user_id ? look.names[row.player_user_id] : undefined;
  const team = row.player_user_id ? look.teamOf[row.player_user_id] : undefined;
  const hole = row.hole ? ordinal(row.hole) : undefined;
  let versus: string | undefined;
  if (m && row.player_user_id) {
    const other = m.team_a_player_ids.includes(row.player_user_id) ? m.team_b_player_ids
      : m.team_b_player_ids.includes(row.player_user_id) ? m.team_a_player_ids : [];
    const names = other.map((id) => look.names[id]).filter(Boolean);
    if (names.length) versus = list(names);
  }
  const context = m ? ` in match ${m.matchup_number}${versus ? ` against ${versus}` : ""}` : "";
  const forTeam = team ? ` for ${team}` : "";

  if (name && hole) {
    switch (row.kind) {
      case "ace":
        return { title: `${name} makes a hole in one`, body: `${name} holed out from the tee on the ${hole} hole${forTeam}${context}. It is the best score a single hole can have.` };
      case "eagle":
        return { title: `${name} eagles the ${hole}`, body: `${name} made an eagle on the ${hole} hole${forTeam}${context}, two shots better than par.` };
      case "birdie":
        return { title: `${name} birdies the ${hole}`, body: `${name} made a birdie on the ${hole} hole${forTeam}${context}.` };
      case "score_change": {
        const change = row.headline.match(/, (\d+) to (\d+)$/);
        const changed = change ? `, changing a ${change[1]} to a ${change[2]}` : "";
        return { title: `Score corrected for ${name}`, body: `A score on the card for ${name} was changed on the ${hole} hole${changed}${context}. Any match totals that depended on it have been recalculated.` };
      }
    }
  }
  if (row.kind === "match_result" && m) {
    const teamName = (id: string) => look.teamNames[id] ?? "A team";
    const side = (ids: string[]) => list(ids.map((id) => look.names[id]).filter(Boolean));
    const a = side(m.team_a_player_ids), b = side(m.team_b_player_ids);
    if (m.result === "team_a_win") return { title: `${teamName(m.team_a_id)} takes match ${m.matchup_number}`, body: `${a} beat ${b} in match ${m.matchup_number} for ${teamName(m.team_a_id)}, worth a point toward the ${look.tournamentName}.` };
    if (m.result === "team_b_win") return { title: `${teamName(m.team_b_id)} takes match ${m.matchup_number}`, body: `${b} beat ${a} in match ${m.matchup_number} for ${teamName(m.team_b_id)}, worth a point toward the ${look.tournamentName}.` };
    if (m.result === "tie") return { title: `Match ${m.matchup_number} is halved`, body: `${a} and ${b} finished match ${m.matchup_number} level, so each team takes half a point toward the ${look.tournamentName}.` };
  }
  return { title: row.headline, body: `${row.headline}.` };
}
