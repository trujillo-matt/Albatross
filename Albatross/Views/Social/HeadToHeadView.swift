import SwiftUI

struct HeadToHeadView: View {
    @Environment(RoundStore.self) private var roundStore

    let myProfile: UserProfile
    let theirProfile: UserProfile
    let theirRounds: [Round]  // Already filtered to completed only

    // MARK: - Computed — My stats

    private var myRounds: [Round] { roundStore.rounds.filter { $0.status == .completed } }

    private var myBest: Int?     { myRounds.map { $0.totalScore }.min() }
    private var theirBest: Int?  { theirRounds.map { $0.totalScore }.min() }

    private var myAvg: Double? {
        guard !myRounds.isEmpty else { return nil }
        return Double(myRounds.map { $0.totalScore }.reduce(0, +)) / Double(myRounds.count)
    }

    private var theirAvg: Double? {
        guard !theirRounds.isEmpty else { return nil }
        return Double(theirRounds.map { $0.totalScore }.reduce(0, +)) / Double(theirRounds.count)
    }

    private var myHcp: Double?    { handicapIndex(for: myRounds) }
    private var theirHcp: Double? { handicapIndex(for: theirRounds) }

    // MARK: - Shared courses

    /// Courses played by both players, with their best scores at each.
    private var sharedCourses: [SharedCourse] {
        let myCourseMap = Dictionary(grouping: myRounds, by: { $0.courseName })
        let theirCourseMap = Dictionary(grouping: theirRounds, by: { $0.courseName })
        let sharedNames = Set(myCourseMap.keys).intersection(Set(theirCourseMap.keys))
        return sharedNames.sorted().compactMap { name -> SharedCourse? in
            guard let myBestHere    = myCourseMap[name]?.map({ $0.totalScore }).min(),
                  let theirBestHere = theirCourseMap[name]?.map({ $0.totalScore }).min()
            else { return nil }
            let par = myCourseMap[name]?.first?.effectivePars.reduce(0, +) ?? 72
            return SharedCourse(courseName: name, par: par,
                                myBest: myBestHere, theirBest: theirBestHere)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    // Versus header
                    versusHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                    // Stat cards
                    statsGrid
                        .padding(.horizontal, 16)

                    // Shared courses
                    if !sharedCourses.isEmpty {
                        sharedCoursesList
                            .padding(.horizontal, 16)
                    } else {
                        noSharedCoursesView
                            .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 40)
                }
                .readableContentWidth()
            }
        }
        .navigationTitle("Head to Head")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Versus header

    private var versusHeader: some View {
        HStack(spacing: 0) {
            // My side
            playerColumn(
                name: myProfile.displayName,
                username: myProfile.username,
                rounds: myRounds.count,
                isLeft: true
            )

            // VS badge
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemGroupedBackground))
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                Text("VS")
                    .appFont(.small, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            .zIndex(1)

            // Their side
            playerColumn(
                name: theirProfile.displayName,
                username: theirProfile.username,
                rounds: theirRounds.count,
                isLeft: false
            )
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.brandGreen))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func playerColumn(name: String, username: String?, rounds: Int, isLeft: Bool) -> some View {
        let initials: String = {
            let parts = name.split(separator: " ")
            return parts.compactMap { $0.first.map(String.init) }.prefix(2).joined()
        }()

        return VStack(spacing: 8) {
            // Avatar
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 56, height: 64)
                Text(initials.isEmpty ? "?" : initials)
                    .appFont(.large, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.85))
            }

            // Name (split two lines if space)
            let parts = name.split(separator: " ", maxSplits: 1)
            VStack(spacing: 0) {
                if parts.count == 2 {
                    Text(String(parts[0]))
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(.white)
                    Text(String(parts[1]))
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(.white)
                } else {
                    Text(name)
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(.white)
                }
                if let username, !username.isEmpty {
                    Text("@\(username)")
                        .appFont(.small)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .multilineTextAlignment(.center)

            Text("\(rounds) round\(rounds == 1 ? "" : "s")")
                .appFont(.small)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Stats grid (2 cols × 3 rows)

    private var statsGrid: some View {
        VStack(spacing: 0) {
            statRow(
                label: "Best Score",
                myValue:    myBest.map    { "\($0)" } ?? "—",
                theirValue: theirBest.map { "\($0)" } ?? "—",
                myWins:     myBest != nil && theirBest != nil && myBest! < theirBest!,
                theirWins:  myBest != nil && theirBest != nil && theirBest! < myBest!,
                isFirst: true
            )
            Divider().padding(.leading, 16)
            statRow(
                label: "Avg Score",
                myValue:    myAvg.map    { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                theirValue: theirAvg.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                myWins:     myAvg != nil && theirAvg != nil && myAvg! < theirAvg!,
                theirWins:  myAvg != nil && theirAvg != nil && theirAvg! < myAvg!,
                isFirst: false
            )
            Divider().padding(.leading, 16)
            statRow(
                label: "Handicap",
                myValue:    myHcp.map    { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                theirValue: theirHcp.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                myWins:     myHcp != nil && theirHcp != nil && myHcp! < theirHcp!,
                theirWins:  myHcp != nil && theirHcp != nil && theirHcp! < myHcp!,
                isFirst: false
            )
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5) }
    }

    private func statRow(label: String, myValue: String, theirValue: String,
                         myWins: Bool, theirWins: Bool, isFirst: Bool) -> some View {
        HStack(spacing: 0) {
            // My value
            HStack {
                Spacer()
                Text(myValue)
                    .appFont(.large, weight: .semibold)
                    .foregroundStyle(myWins ? Color.accentColor : .primary)
                if myWins {
                    Image(systemName: "trophy.fill")
                        .appFont(.small)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity)

            // Centre label
            VStack(spacing: 2) {
                Text(label)
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 72)

            // Their value
            HStack {
                if theirWins {
                    Image(systemName: "trophy.fill")
                        .appFont(.small)
                        .foregroundStyle(Color.accentColor)
                }
                Text(theirValue)
                    .appFont(.large, weight: .semibold)
                    .foregroundStyle(theirWins ? Color.accentColor : .primary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Shared courses table

    private var sharedCoursesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shared Courses")
                .appFont(.body, weight: .semibold)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("Course")
                        .appFont(.small)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("You")
                        .appFont(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .center)
                    Text("Them")
                        .appFont(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .center)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))

                ForEach(sharedCourses) { course in
                    Divider()
                    sharedCourseRow(course)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5) }
        }
    }

    private func sharedCourseRow(_ course: SharedCourse) -> some View {
        let myDiff   = course.myBest - course.par
        let theirDiff = course.theirBest - course.par
        let myWins   = course.myBest < course.theirBest
        let theirWins = course.theirBest < course.myBest

        return HStack(spacing: 0) {
            // Course name
            VStack(alignment: .leading, spacing: 1) {
                Text(course.courseName)
                    .appFont(.small, weight: .medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Par \(course.par)")
                    .appFont(.small)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // My best
            VStack(spacing: 1) {
                Text("\(course.myBest)")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(myWins ? Color.accentColor : .primary)
                Text(myDiff == 0 ? "E" : myDiff > 0 ? "+\(myDiff)" : "\(myDiff)")
                    .appFont(.small)
                    .foregroundStyle(scoreColor(myDiff))
            }
            .frame(width: 52, alignment: .center)

            // Their best
            VStack(spacing: 1) {
                Text("\(course.theirBest)")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(theirWins ? Color.accentColor : .primary)
                Text(theirDiff == 0 ? "E" : theirDiff > 0 ? "+\(theirDiff)" : "\(theirDiff)")
                    .appFont(.small)
                    .foregroundStyle(scoreColor(theirDiff))
            }
            .frame(width: 52, alignment: .center)
        }
        .appListRowPadding()
    }

    private var noSharedCoursesView: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .scaledFont(size: 36)
                .foregroundStyle(.tertiary)
            Text("No Shared Courses")
                .appFont(.body, weight: .semibold)
            Text("Play some of the same courses to see a comparison here.")
                .appFont(.small)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5) }
    }

    // MARK: - Helpers

    private func scoreColor(_ diff: Int) -> Color {
        switch diff {
        case ..<0: return BookletStyle.adaptiveInk(forDifference: -1)
        case 0:    return .secondary
        default:   return .red
        }
    }
}

// MARK: - Model

private struct SharedCourse: Identifiable {
    var id: String { courseName }
    let courseName: String
    let par: Int
    let myBest: Int
    let theirBest: Int
}
