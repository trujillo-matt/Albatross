import SwiftUI

struct CourseSearchView: View {
    @Environment(CourseStore.self) private var courseStore

    /// Called when the user picks a course from results
    var onSelect: (Course) -> Void
    /// Called when the user taps "Enter manually"
    var onManual: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .appFont(.body)

                TextField("Search courses…", text: Bindable(courseStore).searchText)
                    .appFont(.body)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if !courseStore.searchText.isEmpty {
                    Button(action: { courseStore.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            .accessibilityLabel("Clear search")
                    }
                    .buttonStyle(.pressFeedback)
                }
            }
            .appListRowPadding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)

            // Results list
            ScrollView {
                LazyVStack(spacing: 0) {
                    if courseStore.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        suggestedSection
                    } else if courseStore.results.isEmpty {
                        noResults
                    } else {
                        ForEach(courseStore.results.enumerated(), id: \.element.id) { index, course in
                            courseRow(course)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))

                            if index < courseStore.results.count - 1 {
                                Divider()
                                    .padding(.leading, AppSpacing.rowHorizontal + 36 + 12)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 20)

                // "Enter manually" always visible at the bottom
                Button(action: onManual) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                                .frame(width: 36, height: 36)
                            Image(systemName: "pencil")
                                .appFont(.small)
                                .foregroundStyle(.secondary)
                        }

                        Text("Enter course name manually")
                            .appFont(.small)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Image(systemName: "chevron.forward")
                            .appFont(.small, weight: .semibold)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .appListRowPadding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.pressFeedback)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Course row

    private func courseRow(_ course: Course) -> some View {
        Button(action: { onSelect(course) }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image("albatross-mark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(course.locationDisplay)
                        .appFont(.small)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Par \(course.totalPar)")
                        .appFont(.small, weight: .semibold)
                        .foregroundStyle(Color.accentColor)
                    Text("18 holes")
                        .appFont(.small)
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.forward")
                    .appFont(.small, weight: .semibold)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
            .appListRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressFeedback)
    }

    // MARK: - Suggested section (shown when search is empty)

    @ViewBuilder
    private var suggestedSection: some View {
        let preloaded = courseStore.preloadedCourses
        if !preloaded.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .appFont(.small)
                        .foregroundStyle(Color.accentColor)
                    Text("Suggested")
                        .appFont(.small, weight: .medium)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

                ForEach(preloaded.enumerated(), id: \.element.id) { index, course in
                    courseRow(course)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))

                    if index < preloaded.count - 1 {
                        Divider()
                            .padding(.leading, AppSpacing.rowHorizontal + 36 + 12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Empty states

    private var noResults: some View {
        VStack(spacing: 10) {
            IconView("map", size: AppSpacing.listIcon)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
            Text("No courses found for \"\(courseStore.searchText)\"")
                .appFont(.small)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }
}
