export type TournamentStatus = "setup" | "draft" | "active" | "complete";
export type MatchType = "scramble" | "best_ball" | "match_play" | "stroke_play";
export type MatchupStatus = "pending" | "active" | "complete";

export const MATCH_LABEL: Record<MatchType, string> = {
  scramble: "Scramble",
  best_ball: "Best Ball",
  match_play: "Match Play",
  stroke_play: "Stroke Play",
};

export interface Tournament {
  id: string;
  name: string;
  creator_user_id: string;
  status: TournamentStatus;
  match_type: MatchType;
  total_matches: number;
  points_to_win: number;
}
export interface TCourse { id: string; tournament_id: string; course_name: string; round_number: number; match_type: MatchType | null; course_id?: string | null }
export interface TPlayer {
  id: string; tournament_id: string; user_id: string; team_id: string | null;
  invite_status: "pending" | "accepted" | "declined"; is_admin: boolean;
  display_name: string;
}
export interface TTeam { id: string; tournament_id: string; name: string; captain_user_id: string | null; side: "A" | "B" | null }
export interface TVote { id: string; tournament_id: string; voter_user_id: string; nominee_user_id: string }
export interface TMatchup {
  id: string; tournament_id: string; matchup_number: number; team_a_id: string; team_b_id: string;
  team_a_player_ids: string[]; team_b_player_ids: string[]; match_type: MatchType; status: MatchupStatus;
  result: "team_a_win" | "team_b_win" | "tie" | null; points_team_a: number; points_team_b: number;
}
export interface RoundRow {
  id: string; user_id: string; course_name: string; scores: (number | null)[]; status: "in_progress" | "completed";
  course_pars: number[] | null; course_yardages: number[] | null; matchup_id: string | null;
}
export interface TournamentData {
  tournament: Tournament; courses: TCourse[]; players: TPlayer[]; teams: TTeam[]; matchups: TMatchup[]; votes: TVote[];
}
