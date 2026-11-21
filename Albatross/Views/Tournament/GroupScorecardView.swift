import SwiftUI

/// One player keeps score for everyone in the match. The scorer sees every card and a stroke pad;
/// everyone else sees the same cards read-only, refreshed every few seconds.
struct GroupScorecardView: View {
    @EnvironmentObject private var tournamentStore: TournamentStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var courseStore: CourseStore

    let tournament: Tournament
    let matchup: TournamentMatchup

    @State private var cards: [GroupCard] = []
    @State private var hole = 0           // 0-based
    @State private var cardIndex = 0
    @State private var isBusy = false
    @State private var errorMessage: String? = nil
    /// Entries that could not be sent yet: key "roundID|hole" -> strokes (nil clears the hole).
    @State private var unsynced: [String: Int?] = [:]
    @State private var loaded = false

    private var myUserID: UUID? { authStore.currentProfile?.id }
    private var iAmScorer: Bool { myUserID != nil && matchup.scorerUserID == myUserID }
    private var scorerName: String {
        guard let id = matchup.scorerUserID else { return "Someone" }
        return tournament.playerPool.first(where: { $0.userID == id })?.profile?.displayName ?? "A player"
    }

    private func name(of ownerID: UUID) -> String {
        tournament.playerPool.first(where: { $0.userID == ownerID })?.profile?.displayName ?? "Player"
    }

    /// This match and, in singles, the one it is played alongside. One scorer keeps all the cards.
    private var group: [TournamentMatchup] { matchup.foursome(in: tournament.matchups) }

    private func label(for card: GroupCard) -> String {
        guard matchup.scoresOneCardPerSide else { return name(of: card.ownerID) }
        let owning = group.first(where: { $0.includes(card.ownerID) }) ?? matchup
        let isA = owning.teamAPlayerIDs.contains(card.ownerID)
        let team = tournament.teams.first(where: { $0.id == (isA ? owning.teamAID : owning.teamBID) })
        return team?.name ?? (isA ? "Team A" : "Team B")
    }

    /// Cards in display order (side A first within each match), matching the database's owners.
    private var ordered: [GroupCard] {
        let order = group.groupCardOwnerIDs
        return cards.sorted {
            (order.firstIndex(of: $0.ownerID) ?? 99) < (order.firstIndex(of: $1.ownerID) ?? 99)
        }
    }

    private var pars: [Int] {
        if let p = ordered.first?.coursePars, p.count == 18 { return p }
        return Array(repeating: 4, count: 18)
    }

    private func value(_ card: GroupCard, _ h: Int) -> Int? {
        if let pending = unsynced["\(card.id.uuidString)|\(h + 1)"] { return pending }
        return h < card.scores.count ? card.scores[h] : nil
    }

    private var grid: [[Int?]] { ordered.map { c in (0..<18).map { value(c, $0) } } }
    private var allFilled: Bool { !ordered.isEmpty && grid.allSatisfy { $0.allSatisfy { $0 != nil } } }
    private var allSubmitted: Bool { !ordered.isEmpty && ordered.allSatisfy(\.isComplete) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if ordered.isEmpty {
                    emptyState
                } else {
                    if iAmScorer && !allSubmitted { entryPad }
                    cardsTable
                    if iAmScorer && !allSubmitted { actions }
                }

                if !unsynced.isEmpty {
                    HStack {
                        Text("\(unsynced.count) not saved yet")
                            .font(.footnote).foregroundStyle(.orange)
                        Spacer()
                        Button("Retry") { Task { await flushUnsynced() } }
                            .font(.footnote.weight(.semibold))
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Group scorecard")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh(initial: true) }
        .task(id: iAmScorer) {
            // Poll for everyone but the active scorer, whose screen is the source of truth.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !iAmScorer || allSubmitted { await refresh(initial: false) }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(iAmScorer ? "You are keeping score for the group" : "\(scorerName) is keeping score for this group")
                .accessibilityHint(group.count > 1 ? "Covers both matches in the foursome" : "")
                .font(.body.weight(.semibold))
            Text(allSubmitted ? "Submitted. The match result is final."
                 : iAmScorer ? "Enter every player's strokes. Everyone else can watch along."
                 : "These cards update on their own. Only the scorer can change them.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            if iAmScorer {
                Text("The group scorecards have not been started yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    Task { await start() }
                } label: {
                    Text(isBusy ? "Starting…" : "Start the group scorecards")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.brandGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.pressFeedback)
                .disabled(isBusy)
            } else {
                Text(loaded ? "\(scorerName) has not started the scorecards yet." : "Loading…")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var entryPad: some View {
        let card = ordered[min(cardIndex, ordered.count - 1)]
        let par = pars[min(hole, 17)]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { hole = max(0, hole - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(hole == 0)
                Spacer()
                Text("Hole \(hole + 1)  ·  Par \(par)").font(.headline)
                Spacer()
                Button { hole = min(17, hole + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(hole == 17)
            }

            // Which card the next number goes to.
            VStack(spacing: 6) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { i, c in
                    Button { cardIndex = i } label: {
                        HStack {
                            Text(label(for: c)).font(.subheadline)
                            Spacer()
                            Text(value(c, hole).map(String.init) ?? "–")
                                .font(.title3.weight(.semibold)).monospacedDigit()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(i == cardIndex ? Color.brandGreen.opacity(0.15) : Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Strokes for \(label(for: card))").font(.footnote).foregroundStyle(.secondary)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...10, id: \.self) { n in
                    Button { enter(n, card: card) } label: {
                        Text("\(n)").font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.pressFeedback)
                }
            }
            Button("Clear this hole") { enter(nil, card: card) }
                .font(.footnote)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var cardsTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ordered) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(label(for: c)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\((0..<18).compactMap { value(c, $0) }.reduce(0, +))")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(0..<18, id: \.self) { h in
                                VStack(spacing: 2) {
                                    Text("\(h + 1)").font(.caption2).foregroundStyle(.secondary)
                                    Text(value(c, h).map(String.init) ?? "–")
                                        .font(.footnote.weight(.medium)).monospacedDigit()
                                        .frame(width: 26, height: 26)
                                        .background(h == hole && iAmScorer ? Color.brandGreen.opacity(0.2) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await finish() }
            } label: {
                Text(isBusy ? "Submitting…" : "Finish and submit the group scorecards")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(allFilled && unsynced.isEmpty ? Color.brandGreen : Color.gray.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.pressFeedback)
            .disabled(!allFilled || !unsynced.isEmpty || isBusy)

            Button("Step down as scorer") { Task { await stepDown() } }
                .font(.footnote).disabled(isBusy)
        }
    }

    // MARK: - Actions

    private func enter(_ strokes: Int?, card: GroupCard) {
        let h = hole
        let key = "\(card.id.uuidString)|\(h + 1)"
        unsynced[key] = .some(strokes)
        // Advance only when a number was entered, not when clearing.
        if strokes != nil, let next = GroupScoring.nextEmptyCell(scores: grid, hole: h, card: cardIndex) {
            hole = next.hole
            cardIndex = next.card
        }
        Task { await flushUnsynced() }
    }

    private func flushUnsynced() async {
        for (key, strokes) in unsynced {
            let parts = key.split(separator: "|")
            guard parts.count == 2, let rid = UUID(uuidString: String(parts[0])), let h = Int(parts[1]) else { continue }
            do {
                try await tournamentStore.setHoleScore(roundID: rid, hole: h, strokes: strokes)
                // Mirror into the local copy, then drop it from the queue (unless it changed meanwhile).
                if let i = cards.firstIndex(where: { $0.id == rid }), h - 1 < cards[i].scores.count {
                    cards[i].scores[h - 1] = strokes
                }
                if let current = unsynced[key], current == strokes { unsynced[key] = nil }
                errorMessage = nil
            } catch {
                errorMessage = "Could not save. Your entries are kept here. \(error.localizedDescription)"
                return
            }
        }
    }

    private func refresh(initial: Bool) async {
        let fetched = await tournamentStore.fetchGroupCards(matchupIDs: group.map(\.id))
        loaded = true
        guard !fetched.isEmpty else { cards = []; return }
        cards = fetched
        if initial, iAmScorer, let cell = GroupScoring.firstEmptyCell(scores: grid) {
            hole = cell.hole
            cardIndex = cell.card
        }
    }

    private func course() -> Course? {
        let wanted = courseNameForMatch.lowercased()
        return courseStore.allCourses.first {
            $0.name.lowercased() == wanted || $0.shortName?.lowercased() == wanted
        }
    }

    private var courseNameForMatch: String {
        if let id = matchup.sessionID, let s = tournament.sessions.first(where: { $0.id == id }) {
            if let n = s.courseName, !n.isEmpty { return n }
            return tournament.courses.first(where: { $0.roundNumber == s.dayNumber })?.courseName ?? "Tournament round"
        }
        return tournament.courses.first(where: { $0.roundNumber == matchup.matchupNumber })?.courseName ?? "Tournament round"
    }

    private func start() async {
        isBusy = true; defer { isBusy = false }
        do {
            try await tournamentStore.startGroupScoring(matchupID: matchup.id, courseName: courseNameForMatch, course: course())
            errorMessage = nil
            await refresh(initial: true)
        } catch { errorMessage = error.localizedDescription }
    }

    private func finish() async {
        isBusy = true; defer { isBusy = false }
        await flushUnsynced()
        guard unsynced.isEmpty else { return }
        do {
            try await tournamentStore.finishGroupScoring(matchupID: matchup.id, tournamentID: tournament.id)
            errorMessage = nil
            await refresh(initial: false)
        } catch { errorMessage = error.localizedDescription }
    }

    private func stepDown() async {
        isBusy = true; defer { isBusy = false }
        do {
            try await tournamentStore.setScorer(matchupID: matchup.id, tournamentID: tournament.id, scorerID: nil)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
