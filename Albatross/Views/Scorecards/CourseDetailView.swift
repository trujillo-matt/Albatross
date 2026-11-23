import SwiftUI

struct CourseDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let round: Round
    let course: Course?

    // MARK: - Resolved data (course first, round as fallback)

    private var courseName: String { course?.name ?? round.courseName }
    private var location: String? { course?.locationDisplay }
    private var architect: String? { course?.architect }
    private var yearBuilt: Int? { course?.yearBuilt }
    private var courseRating: Double? { course?.courseRating ?? round.courseRating }
    private var slopeRating: Int? { course?.slopeRating ?? round.slopeRating }
    private var totalPar: Int? { course.map { $0.totalPar } }
    private var totalYards: Int? { course.map { $0.holes.map(\.yardage).reduce(0, +) } }
    private var teeOptions: [TeeOption]? { course?.teeOptions }
    private var website: String? { course?.website }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Green banner header ───────────────────────────────────
                bannerHeader
                    .padding(.bottom, 24)

                VStack(spacing: 14) {
                    // ── Course facts ──────────────────────────────────────
                    courseStatsCard

                    // ── Design (architect / year) ─────────────────────────
                    if architect != nil || yearBuilt != nil {
                        designCard
                    }

                    // ── Website ───────────────────────────────────────────
                    if let site = website, !site.isEmpty {
                        websiteCard(site)
                    }

                    // ── Tee options ───────────────────────────────────────
                    if let tees = teeOptions, !tees.isEmpty {
                        teesCard(tees)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    // MARK: - Banner

    private var bannerHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Accent green fill
            Color.brandGreen
                .frame(maxWidth: .infinity)
                .frame(height: 180)

            // Subtle flag watermark
            IconView("flag", size: 96)
                .foregroundStyle(.white.opacity(0.08))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 24)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text(courseName)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let loc = location {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .appFont(.small)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(loc)
                            .appFont(.small)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Stats card

    private var courseStatsCard: some View {
        sectionCard(title: "The Course") {
            Group {
                if let rating = courseRating {
                    infoRow(label: "Rating", value: rating.formatted(.number.precision(.fractionLength(1))))
                }
                if let slope = slopeRating {
                    infoRow(label: "Slope", value: "\(slope)", isLast: totalPar == nil && totalYards == nil)
                }
                if let par = totalPar {
                    infoRow(label: "Par", value: "\(par)", isLast: totalYards == nil)
                }
                if let yards = totalYards {
                    infoRow(label: "Total Yards", value: yards.formatted(), isLast: true)
                }
            }
        }
    }

    // MARK: - Design card

    private var designCard: some View {
        sectionCard(title: "Design") {
            Group {
                if let arc = architect {
                    infoRow(label: "Architect", value: arc, isLast: yearBuilt == nil)
                }
                if let year = yearBuilt {
                    infoRow(label: "Year Built", value: "\(year)", isLast: true)
                }
            }
        }
    }

    // MARK: - Website card

    private func websiteCard(_ site: String) -> some View {
        let urlString = site.hasPrefix("http") ? site : "https://\(site)"
        return sectionCard(title: nil) {
            Button(action: {
                if let url = URL(string: urlString) {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack {
                    Image(systemName: "globe")
                        .appFont(.small)
                        .foregroundStyle(Color.accentColor)
                    Text(site)
                        .appFont(.small)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                }
                .appListRowPadding()
            }
            .buttonStyle(.pressFeedback)
        }
    }

    // MARK: - Tees card

    private func teesCard(_ tees: [TeeOption]) -> some View {
        sectionCard(title: "Tees") {
            ForEach(tees.enumerated(), id: \.element) { index, tee in
                HStack(spacing: 0) {
                    // Tee name badge
                    Text(tee.name)
                        .appFont(.small, weight: .medium)
                        .foregroundStyle(.primary)
                        .frame(width: 56, alignment: .leading)
                        .padding(.leading, 16)

                    Text("\(tee.totalYards.formatted()) yds")
                        .appFont(.small)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let rating = tee.rating, let slope = tee.slope {
                        Text("\(rating.formatted(.number.precision(.fractionLength(1)))) / \(slope)")
                            .appFont(.small)
                            .foregroundStyle(.tertiary)
                            .padding(.trailing, 16)
                    }
                }
                .padding(.vertical, 10)

                if index < tees.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - Section card wrapper

    @ViewBuilder
    private func sectionCard(title: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .appFont(.small, weight: .medium)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.bottom, 6)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Info row

    private func infoRow(label: String, value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .appFont(.small)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .appFont(.small, weight: .medium)
                    .foregroundStyle(.primary)
            }
            .appListRowPadding()

            if !isLast {
                Divider().padding(.leading, 16)
            }
        }
    }
}
