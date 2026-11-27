import SwiftUI
import WeatherKit

struct TournamentListView: View {
    @Environment(TournamentStore.self) private var tournamentStore
    @Environment(AuthStore.self) private var authStore

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showNewTournament = false
    @State private var tournamentToDelete: Tournament? = nil
    @State private var showDeleteAlert = false

    private func reloadTournaments() async {
        await tournamentStore.loadMyTournaments()
        await tournamentStore.loadPendingInvites()
    }

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    // Wide screens: the news and tournament info on the left, the leaderboard on the right.
                    // Each side scrolls on its own, so a long board does not push the news away.
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView { VStack(alignment: .leading, spacing: 28) { newsColumn }.padding(16) }
                        ScrollView { VStack(alignment: .leading, spacing: 28) { standingsColumn }.padding(16) }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            standingsColumn
                            newsColumn
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Tournaments")
            .tabMenuToolbar()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showNewTournament = true }) {
                        Label("New tournament", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewTournament) {
                NewTournamentSheet()
            }
            .alert("Delete tournament?", isPresented: $showDeleteAlert, presenting: tournamentToDelete) { t in
                Button("Delete", role: .destructive) {
                    Task { try? await tournamentStore.deleteTournament(t) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { t in
                Text("\u{201C}\(t.name)\u{201D} and all its data will be permanently deleted. This cannot be undone.")
            }
            .task {
                await reloadTournaments()
            }
            // Tournaments made or changed elsewhere (the web app, another phone) show up on return and on pull down.
            .refreshable { await reloadTournaments() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await reloadTournaments() } }
            }
            // The board stays current while it is on screen: results and scores are refreshed every few seconds.
            .task(id: featuredTournament?.id) {
                guard let id = featuredTournament?.id else { return }
                while !Task.isCancelled {
                    await tournamentStore.refreshLive(for: id)
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
    }

    // MARK: - Columns

    @ViewBuilder private var standingsColumn: some View {
        if !tournamentStore.pendingInvites.isEmpty {
            pendingInvitesSection
        }
        if let featured = featuredTournament {
            leaderboardSection(featured)
        }
        if tournamentStore.myTournaments.isEmpty && tournamentStore.pendingInvites.isEmpty {
            emptyTournamentState
        }
    }

    @ViewBuilder private var newsColumn: some View {
        if let featured = featuredTournament {
            TournamentInfoCard(tournament: featured)
            TournamentForecastSection(tournament: featured)
        }
        if !tournamentStore.myTournaments.isEmpty {
            TournamentNewsFeed()
            VStack(alignment: .leading, spacing: 12) {
                Text("All tournaments")
                    .appFont(.large, weight: .medium)
                    .accessibilityAddTraits(.isHeader)
                tournamentList
            }
        }
    }

    // MARK: - Pending invites

    private var pendingInvitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.badge.fill")
                    .appFont(.small)
                    .foregroundStyle(Color.accentColor)
                Text("\(tournamentStore.pendingInvites.count) pending invite\(tournamentStore.pendingInvites.count == 1 ? "" : "s")")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ForEach(tournamentStore.pendingInvites) { tournament in
                pendingInviteRow(tournament)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func pendingInviteRow(_ tournament: Tournament) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tournament.name)
                    .appFont(.small, weight: .medium)
                    .foregroundStyle(.primary)
                Text(tournament.matchType.displayName)
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    Task { try? await tournamentStore.declineInvite(tournamentID: tournament.id) }
                }) {
                    Text("Decline")
                        .appFont(.small)
                        .appButton(fill: Color(uiColor: .systemFill), foreground: .secondary, fullWidth: false, cornerRadius: AppSpacing.buttonHeight / 2)
                }
                .buttonStyle(.pressFeedback)

                Button(action: {
                    Task { try? await tournamentStore.acceptInvite(tournamentID: tournament.id) }
                }) {
                    Text("Accept")
                        .appFont(.small, weight: .medium)
                        .appButton(fill: Color.brandGreen, foreground: .white, fullWidth: false, cornerRadius: AppSpacing.buttonHeight / 2)
                }
                .buttonStyle(.pressFeedback)
            }
        }
        .appListRowPadding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: - Leaderboard

    /// The tournament the board shows: the one being played, otherwise the newest.
    private var featuredTournament: Tournament? {
        let withMatches = tournamentStore.myTournaments.filter { !$0.matchups.isEmpty && $0.teams.count == 2 }
        return withMatches.first { $0.status == .active } ?? withMatches.first
    }

    private func leaderboardSection(_ tournament: Tournament) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standings")
                .appFont(.large, weight: .medium)
                .accessibilityAddTraits(.isHeader)
            NavigationLink {
                TournamentDetailView(tournament: tournament)
            } label: {
                TournamentLeaderboard(tournament: tournament)
            }
            .buttonStyle(.pressFeedback)
        }
    }

    // MARK: - Tournament list

    private var tournamentList: some View {
        VStack(spacing: 12) {
            ForEach(tournamentStore.myTournaments) { tournament in
                NavigationLink {
                    TournamentDetailView(tournament: tournament)
                } label: {
                    tournamentCard(tournament)
                }
                .buttonStyle(.pressFeedback)
                .contextMenu {
                    Button(role: .destructive) {
                        tournamentToDelete = tournament
                        showDeleteAlert = true
                    } label: {
                        Label("Delete tournament", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func tournamentCard(_ tournament: Tournament) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(tournament.status))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(statusLabel(tournament.status))
                        .appFont(.small)
                        .foregroundStyle(statusColor(tournament.status))
                }
                Text(tournament.name)
                    .appFont(.large, weight: .semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(tournamentSummary(tournament))
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .appFont(.small, weight: .semibold)
                .foregroundStyle(.tertiary)
        }
        .appListRowPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Empty state

    private var emptyTournamentState: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconView("trophy", size: AppSpacing.listIcon)
                .foregroundStyle(Color.accentColor)
            Text("No tournaments yet")
                .appFont(.large, weight: .semibold)
            Text("Create one, invite friends, and score each match on a booklet.")
                .appFont(.small)
                .foregroundStyle(.secondary)
            Button(action: { showNewTournament = true }) {
                Text("Create a tournament")
                    .appFont(.small, weight: .medium)
                    .appButton(fill: Color.brandGreen, foreground: .white, fullWidth: false)
            }
            .buttonStyle(.pressFeedback)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Helpers

    /// "3 days · 18 matches", or just the days until the players are set and the matches known.
    private func tournamentSummary(_ tournament: Tournament) -> String {
        let days = "\(tournament.dayCount) day\(tournament.dayCount == 1 ? "" : "s")"
        guard !tournament.matchups.isEmpty else { return days }
        let matches = tournament.matchCount
        return "\(days) · \(matches) match\(matches == 1 ? "" : "es")"
    }

    private func statusColor(_ status: TournamentStatus) -> Color {
        switch status {
        case .setup:    return .secondary
        case .draft:    return .orange
        case .active:   return .accentColor
        case .complete: return .secondary
        }
    }

    private func statusLabel(_ status: TournamentStatus) -> String {
        switch status {
        case .setup:    return "Setup"
        case .draft:    return "Draft"
        case .active:   return "Active"
        case .complete: return "Complete"
        }
    }
}


/// "Tournament news": birdies, changed scores and finished matches from my tournaments.
/// Refreshes while it is on screen.
struct TournamentNewsFeed: View {
    @Environment(TournamentStore.self) private var tournamentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tournament news")
                .appFont(.large, weight: .medium)
                .accessibilityAddTraits(.isHeader)

            if tournamentStore.news.isEmpty {
                Text("Birdies, changed scores and finished matches show up here")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                let stories = tournamentStore.news.map {
                    ($0, NewsStoryWriter.story(for: $0, in: tournamentStore.myTournaments, liveStatus: tournamentStore.liveStatus))
                }
                VStack(spacing: 0) {
                    ForEach(stories, id: \.0.id) { item, story in
                        NewsRow(item: item, story: story)
                        if item.id != tournamentStore.news.last?.id { Divider().padding(.leading, 34) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task { await tournamentStore.loadNews() }
    }
}


/// One line of news: a dot for the kind, the headline, the sentence under it and when it happened.
private struct NewsRow: View {
    let item: TournamentNewsItem
    let story: NewsStory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(item.kind == "score_change" ? Color.orange : (item.kind == "match_result" ? Color.secondary : Color.brandGreen))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(story.title)
                    .appFont(.small, weight: .semibold)
                Text(story.body)
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .appFont(.small)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .appListRowPadding()
        .accessibilityElement(children: .combine)
    }
}

/// What the tournament is: where it is played, in what format, and what it takes to win.
struct TournamentInfoCard: View {
    let tournament: Tournament

    private var courses: String {
        var names = tournament.sessions.sorted { ($0.dayNumber, $0.sessionNumber) < ($1.dayNumber, $1.sessionNumber) }.compactMap(\.courseName)
        if names.isEmpty { names = tournament.courses.map(\.courseName) }
        return names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.formatted(.list(type: .and))
    }

    private var formats: String {
        var types = tournament.sessions.map(\.matchType)
        if types.isEmpty { types = [tournament.matchType] }
        return types.reduce(into: [TournamentMatchType]()) { if !$0.contains($1) { $0.append($1) } }
            .map(\.displayName).formatted(.list(type: .and))
    }

    private var teams: String {
        tournament.teams.map(\.name).formatted(.list(type: .and))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tournament info")
                .appFont(.large, weight: .medium)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                row("Format", formats)
                row("Courses", courses)
                row("Teams", teams)
                row("To win", "\(tournament.pointsToWin.formatted(.number.precision(.fractionLength(0...1)))) points")
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .appFont(.small)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .appFont(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appListRowPadding()
        .accessibilityElement(children: .combine)
    }
}


/// The forecast for each round day, from Apple Weather. Left out when there is nothing to show, which includes a build
/// without the WeatherKit capability.
struct TournamentForecastSection: View {
    let tournament: Tournament
    @Environment(WeatherForecastStore.self) private var weather
    @Environment(CourseStore.self) private var courseStore

    var body: some View {
        Group {
            if weather.status == .ready, !weather.forecasts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Forecast")
                        .appFont(.large, weight: .medium)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(weather.forecasts) { forecast in
                            ForecastRow(forecast: forecast)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // Apple requires its mark and a link to the data sources wherever its forecasts appear, so this is
                    // always shown with them, whether or not the mark itself could be fetched.
                    WeatherAttributionView(attribution: weather.attribution)
                }
            }
        }
        .task(id: tournament.teeTimes.count) {
            await weather.load(for: tournament, courses: courseStore.allCourses)
        }
    }
}

private struct ForecastRow: View {
    let forecast: RoundForecast

    /// Whole degrees in the viewer's own unit; WeatherKit's values carry many decimals.
    private static let temperature = Measurement<UnitTemperature>.FormatStyle(
        width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
    private static let speed = Measurement<UnitSpeed>.FormatStyle(
        width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: forecast.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Day \(forecast.dayNumber), \(forecast.date.formatted(.dateTime.weekday(.wide)))")
                    .appFont(.small, weight: .semibold)
                Text("\(forecast.condition) at \(forecast.courseName)")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                if forecast.isRainLikely {
                    Text("Rain likely: \(forecast.rainChance.formatted(.percent.precision(.fractionLength(0)))) chance")
                        .appFont(.small, weight: .medium)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(forecast.high.formatted(Self.temperature)) / \(forecast.low.formatted(Self.temperature))")
                    .appFont(.small, monospacedDigit: true)
                Text("Wind \(forecast.windSpeed.formatted(Self.speed))")
                    .appFont(.small, monospacedDigit: true)
                    .foregroundStyle(.secondary)
            }
        }
        .appListRowPadding()
        .accessibilityElement(children: .combine)
    }
}

/// Apple requires its Weather mark and a link to the data sources wherever its forecasts appear.
/// If the mark cannot be loaded the words "Apple Weather" stand in for it; the link always works.
private struct WeatherAttributionView: View {
    let attribution: WeatherAttribution?
    @Environment(\.colorScheme) private var colorScheme

    /// Apple's own page on where the data comes from, used when WeatherKit has not supplied the link.
    private static let fallbackLegalPage = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        HStack(spacing: 8) {
            mark
                .frame(height: 14)
                .accessibilityLabel("Apple Weather")
            Link("Data sources", destination: attribution?.legalPageURL ?? Self.fallbackLegalPage)
                .appFont(.small)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var mark: some View {
        if let attribution {
            AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text("Apple Weather").appFont(.small, weight: .medium)
            }
        } else {
            Text("Apple Weather").appFont(.small, weight: .medium)
        }
    }
}
