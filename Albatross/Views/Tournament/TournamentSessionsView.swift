import SwiftUI

/// A day at a time: each session's auto-filled lineup, then the captains' callouts, then the locked matches.
/// Every rule lives in the database (migration 008); this view shows state and sends the captain's choice.
struct TournamentSessionsView: View {
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var authStore: AuthStore

    let tournamentID: UUID

    @State private var selectedDay: Int? = nil
    @State private var myUnit: [UUID]? = nil
    @State private var theirUnit: [UUID]? = nil
    @State private var pickedPlayer: UUID? = nil
    @State private var isWorking = false
    @State private var errorMessage: String? = nil

    /// Read from the store each time so realtime reloads update the screen.
    private var tournament: Tournament? {
        tournamentStore.myTournaments.first(where: { $0.id == tournamentID })
    }
    private var myUserID: UUID? { authStore.currentProfile?.id }

    var body: some View {
        ScrollView {
            if let tournament {
                VStack(alignment: .leading, spacing: 16) {
                    dayPicker(tournament)
                    ForEach(sessions(in: tournament)) { session in
                        sessionCard(session, tournament: tournament)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Lineups & Callouts")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Days

    private func dayNumbers(_ t: Tournament) -> [Int] {
        Array(Set(t.sortedSessions.map(\.dayNumber))).sorted()
    }

    private func shownDay(_ t: Tournament) -> Int {
        selectedDay ?? t.currentSession?.dayNumber ?? 1
    }

    private func sessions(in t: Tournament) -> [TournamentSession] {
        t.sortedSessions.filter { $0.dayNumber == shownDay(t) }
    }

    private func dayPicker(_ t: Tournament) -> some View {
        Picker("Day", selection: Binding(get: { shownDay(t) }, set: { selectedDay = $0 })) {
            ForEach(dayNumbers(t), id: \.self) { number in
                Text("Day \(number)").tag(number)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Names and permissions

    private func name(_ id: UUID, _ t: Tournament) -> String {
        t.playerPool.first(where: { $0.userID == id })?.profile?.displayName ?? "Player"
    }

    private func unitName(_ unit: [UUID], _ t: Tournament) -> String {
        unit.map { name($0, t) }.joined(separator: " & ")
    }

    private func teamName(_ id: UUID?, _ t: Tournament) -> String {
        t.teams.first(where: { $0.id == id })?.name ?? ""
    }

    private func isCaptain(of teamID: UUID?, _ t: Tournament) -> Bool {
        guard let me = myUserID, let teamID else { return false }
        return t.teams.first(where: { $0.id == teamID })?.captainUserID == me
    }

    private func isAdmin(_ t: Tournament) -> Bool {
        guard let me = myUserID else { return false }
        return me == t.creatorUserID || t.playerPool.contains(where: { $0.userID == me && $0.isAdmin })
    }

    private func canManage(_ t: Tournament) -> Bool {
        isAdmin(t) || t.teams.contains(where: { isCaptain(of: $0.id, t) })
    }

    private func canEdit(team teamID: UUID, _ t: Tournament) -> Bool {
        isAdmin(t) || isCaptain(of: teamID, t)
    }

    private func canCall(_ session: TournamentSession, _ t: Tournament) -> Bool {
        session.status == .callouts && (isCaptain(of: session.turnTeamID, t) || isAdmin(t))
    }

    /// Team A is the first team, matching how the database orders sides.
    private func sideIsA(_ unitSideTeam: UUID, _ t: Tournament) -> Bool {
        t.teams.first?.id == unitSideTeam
    }

    private func unit(of match: TournamentMatchup, teamA: Bool) -> [UUID] {
        teamA ? match.teamAPlayerIDs : match.teamBPlayerIDs
    }

    // MARK: - Session card

    private func sessionCard(_ session: TournamentSession, tournament t: Tournament) -> some View {
        let matches = t.matchups(in: session)
        let open = matches.filter { !$0.isLockedIn }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.title), \(session.matchType.displayName)")
                        .font(.callout.weight(.semibold))
                    Text("\(session.courseName ?? "Course to be set") · \(session.matchCount) matches")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(session.status.displayName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            if session.status == .callouts {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(teamName(session.turnTeamID, t)) to call")
                        .font(.subheadline.weight(.semibold))
                    Text(calloutHint(session, t, open: open, locked: matches.count - open))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if session.status == .pending {
                Text("The lineup is made when the previous session finishes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(matches) { match in
                    matchRow(match, session: session, tournament: t)
                }
            }

            if session.status == .lineup {
                sitOutSection(session, matches: matches, tournament: t)
                if canManage(t) {
                    HStack {
                        Button("Re-autofill") { run { try await tournamentStore.autofillSession(session) } }
                            .buttonStyle(.bordered)
                        Button("Open callouts") { run { try await tournamentStore.openCallouts(session) } }
                            .buttonStyle(.borderedProminent)
                    }
                    .disabled(isWorking)
                }
                Text("Tap two players on the same team to swap them. Callouts start when a captain opens them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if canCall(session, t) {
                callControls(session, tournament: t)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func calloutHint(_ session: TournamentSession, _ t: Tournament, open: Int, locked: Int) -> String {
        var text = isCaptain(of: session.turnTeamID, t)
            ? "Pick one of your units, then the opponent you want."
            : (canCall(session, t) ? "You are acting as admin." : "Waiting for their captain.")
        text += " \(open) open, \(locked) locked."
        if session.consecutivePasses >= 1 { text += " A pass now locks the rest as they stand." }
        return text
    }

    // MARK: - Match rows

    private func matchRow(_ match: TournamentMatchup, session: TournamentSession, tournament t: Tournament) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Match \(match.matchupNumber)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(matchCaption(match, session: session, t))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                side(match, teamA: true, session: session, tournament: t)
                Text("vs").font(.caption).foregroundStyle(.secondary)
                side(match, teamA: false, session: session, tournament: t)
            }
        }
    }

    private func matchCaption(_ match: TournamentMatchup, session: TournamentSession, _ t: Tournament) -> String {
        if match.status == .complete { return "\(format(match.pointsTeamA)) to \(format(match.pointsTeamB))" }
        if match.isLockedIn {
            return match.calledByTeamID != nil ? "Called by \(teamName(match.calledByTeamID, t))" : "Locked"
        }
        return session.status == .callouts ? "Open" : ""
    }

    private func format(_ points: Double) -> String {
        points == points.rounded() ? String(Int(points)) : String(points)
    }

    @ViewBuilder
    private func side(_ match: TournamentMatchup, teamA: Bool, session: TournamentSession, tournament t: Tournament) -> some View {
        let units = unit(of: match, teamA: teamA)
        let teamID = teamA ? match.teamAID : match.teamBID
        if session.status == .lineup {
            VStack(spacing: 4) {
                ForEach(units, id: \.self) { id in
                    Button {
                        tapPlayer(id, team: teamID, session: session, tournament: t)
                    } label: {
                        Text(name(id, t))
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(pickedPlayer == id ? Color.accentColor.opacity(0.25) : Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking || !canEdit(team: teamID, t))
                }
            }
        } else {
            let isMine = canCall(session, t) && sideIsA(teamID, t) == turnIsA(session, t)
            let selected = (isMine ? myUnit : theirUnit).map { Set($0) == Set(units) } ?? false
            Button {
                tapUnit(units, isMine: isMine, locked: match.isLockedIn, session: session, tournament: t)
            } label: {
                Text(unitName(units, t).isEmpty ? "TBD" : unitName(units, t))
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selected ? Color.accentColor.opacity(0.25) : Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isWorking || match.isLockedIn || !canCall(session, t))
        }
    }

    private func turnIsA(_ session: TournamentSession, _ t: Tournament) -> Bool {
        guard let turn = session.turnTeamID else { return false }
        return sideIsA(turn, t)
    }

    // MARK: - Lineup: sit-outs and swaps

    @ViewBuilder
    private func sitOutSection(_ session: TournamentSession, matches: [TournamentMatchup], tournament t: Tournament) -> some View {
        ForEach(t.teams.prefix(2)) { team in
            let teamA = sideIsA(team.id, t)
            let playing = Set(matches.flatMap { unit(of: $0, teamA: teamA) })
            let out = t.playerPool.filter { $0.teamID == team.id && $0.inviteStatus == .accepted && !playing.contains($0.userID) }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(team.name) sitting out")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                if out.isEmpty {
                    Text("Everyone plays").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(out) { player in
                        Button {
                            tapPlayer(player.userID, team: team.id, session: session, tournament: t)
                        } label: {
                            Text(player.profile?.displayName ?? "Player")
                                .font(.callout)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(pickedPlayer == player.userID ? Color.accentColor.opacity(0.25) : Color(.tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking || !canEdit(team: team.id, t))
                    }
                }
            }
        }
    }

    /// Tap one player, then another on the same team, to swap them. A sit-out can swap in for a starter.
    private func tapPlayer(_ id: UUID, team teamID: UUID, session: TournamentSession, tournament t: Tournament) {
        guard let first = pickedPlayer else { pickedPlayer = id; return }
        let sameTeam = t.playerPool.first(where: { $0.userID == first })?.teamID == teamID
        if first == id { pickedPlayer = nil; return }
        if !sameTeam { pickedPlayer = id; return }
        let teamA = sideIsA(teamID, t)
        let units: [[UUID]] = t.matchups(in: session).map { match in
            unit(of: match, teamA: teamA).map { current in
                current == first ? id : (current == id ? first : current)
            }
        }
        pickedPlayer = nil
        run { try await tournamentStore.setSessionSide(session, teamID: teamID, units: units) }
    }

    // MARK: - Callouts

    private func tapUnit(_ units: [UUID], isMine: Bool, locked: Bool, session: TournamentSession, tournament t: Tournament) {
        guard !locked, canCall(session, t) else { return }
        if isMine {
            myUnit = (myUnit.map { Set($0) == Set(units) } ?? false) ? nil : units
        } else {
            theirUnit = (theirUnit.map { Set($0) == Set(units) } ?? false) ? nil : units
        }
    }

    @ViewBuilder
    private func callControls(_ session: TournamentSession, tournament t: Tournament) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let myUnit, let theirUnit {
                Text("Call out \(unitName(myUnit, t)) against \(unitName(theirUnit, t))")
                    .font(.subheadline)
            }
            HStack {
                Button("Call it out") {
                    guard let mine = myUnit, let theirs = theirUnit else { return }
                    let asAdmin = !isCaptain(of: session.turnTeamID, t)
                    run { try await tournamentStore.makeCallout(session, myUnit: mine, theirUnit: theirs, asAdmin: asAdmin) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(myUnit == nil || theirUnit == nil || isWorking)

                Button("Pass") {
                    let asAdmin = !isCaptain(of: session.turnTeamID, t)
                    run { try await tournamentStore.passCallout(session, asAdmin: asAdmin) }
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
        }
    }

    // MARK: - Running an action

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await action()
                await MainActor.run {
                    myUnit = nil
                    theirUnit = nil
                    pickedPlayer = nil
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isWorking = false }
        }
    }
}
