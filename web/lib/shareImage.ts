import type { TournamentData } from "./types";
import { orderedTeams } from "./draft";
import { MATCH_LABEL } from "./types";

/** Draws a 1080x1920 standings card, the web equivalent of the iOS StandingsShareCard. */
export async function renderStandingsImage(data: TournamentData): Promise<Blob> {
  const W = 1080, H = 1920, green = "#243627";
  const c = document.createElement("canvas"); c.width = W; c.height = H;
  const g = c.getContext("2d")!;
  g.fillStyle = "#faf8f2"; g.fillRect(0, 0, W, H);
  g.fillStyle = green; g.fillRect(0, 0, W, 18); g.fillRect(0, H - 18, W, 18);
  g.textAlign = "center";

  g.fillStyle = green; g.font = "bold 40px Georgia, serif"; g.fillText("A L B A T R O S S", W / 2, 150);
  g.fillStyle = "#111"; g.font = "bold 72px Georgia, serif"; g.fillText(data.tournament.name, W / 2, 270, W - 120);

  const [a, b] = orderedTeams(data.teams);
  const pa = data.matchups.reduce((s, m) => s + Number(m.points_team_a), 0);
  const pb = data.matchups.reduce((s, m) => s + Number(m.points_team_b), 0);
  if (a && b) {
    for (const [x, team, pts, lead] of [[W * 0.27, a, pa, pa > pb], [W * 0.73, b, pb, pb > pa]] as const) {
      g.fillStyle = "#111"; g.font = "bold 52px Georgia, serif"; g.fillText(team.name, x, 560, 440);
      g.fillStyle = lead ? green : "#555"; g.font = "bold 220px Georgia, serif"; g.fillText(pts.toFixed(1), x, 780);
    }
    g.fillStyle = "#bbb"; g.fillRect(W / 2 - 1, 440, 2, 380);
    g.fillStyle = "#777"; g.font = "36px Georgia, serif";
    g.fillText(`First to ${Number(data.tournament.points_to_win).toFixed(1)} wins`, W / 2, 900);
  }

  g.font = "38px Georgia, serif";
  const name = (id: string) => data.teams.find((t) => t.id === id)?.name ?? "?";
  data.matchups.slice(0, 14).forEach((m, i) => {
    const y = 1040 + i * 56;
    g.textAlign = "left"; g.fillStyle = "#777"; g.fillText(`Match ${m.matchup_number} · ${MATCH_LABEL[m.match_type]}`, 90, y);
    g.textAlign = "right"; g.fillStyle = "#333";
    g.fillText(m.status === "complete" ? `${name(m.team_a_id)} ${Number(m.points_team_a).toFixed(1)} to ${Number(m.points_team_b).toFixed(1)} ${name(m.team_b_id)}` : m.status === "active" ? "In progress" : "Pending", W - 90, y);
  });

  return new Promise((res, rej) => c.toBlob((b) => (b ? res(b) : rej(new Error("Could not render image"))), "image/png"));
}

/** Uses the native share sheet when it can share files (phones), otherwise downloads the PNG. */
export async function shareOrDownload(blob: Blob, filename: string) {
  const file = new File([blob], filename, { type: "image/png" });
  if (navigator.canShare?.({ files: [file] })) { await navigator.share({ files: [file] }); return; }
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a"); a.href = url; a.download = filename; a.click();
  URL.revokeObjectURL(url);
}
