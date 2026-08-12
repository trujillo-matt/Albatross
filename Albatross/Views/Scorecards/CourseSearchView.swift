import SwiftUI

struct CourseSearchView: View {
    @EnvironmentObject private var courseStore: CourseStore

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
                    .font(.system(size: 15))

                TextField("Search courses…", text: $courseStore.searchText)
                    .font(.custom("Baskerville", size: 16))
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if !courseStore.searchText.isEmpty {
                    Button(action: { courseStore.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        ForEach(Array(courseStore.results.enumerated()), id: \.element.id) { index, course in
                            courseRow(course)
                                .background(Color(.secondarySystemGroupedBackground))

                            if index < courseStore.results.count - 1 {
                                Divider()
                                    .padding(.leading, 60)
                                    .background(Color(.secondarySystemGroupedBackground))
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)

                // "Enter manually" always visible at the bottom
                Button(action: onManual) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.tertiarySystemGroupedBackground))
                                .frame(width: 36, height: 36)
                            Image(systemName: "pencil")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }

                        Text("Enter course name manually")
                            .font(.custom("Baskerville", size: 15))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
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
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image("black-browed-albatross")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .opacity(0.6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(.custom("Baskerville-Bold", size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(course.locationDisplay)
                        .font(.custom("Baskerville", size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Par \(course.totalPar)")
                        .font(.custom("Baskerville-Bold", size: 13))
                        .foregroundStyle(Color.accentColor)
                    Text("18 holes")
                        .font(.custom("Baskerville", size: 10))
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Suggested section (shown when search is empty)

    @ViewBuilder
    private var suggestedSection: some View {
        let preloaded = courseStore.preloadedCourses
        if !preloaded.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    Text("Suggested")
                        .font(.custom("Baskerville-SemiBold", size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

                ForEach(Array(preloaded.enumerated()), id: \.element.id) { index, course in
                    courseRow(course)
                        .background(Color(.secondarySystemGroupedBackground))

                    if index < preloaded.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                            .background(Color(.secondarySystemGroupedBackground))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Empty states

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.slash")
                .font(.system(size: 28))
                .foregroundStyle(Color(.tertiaryLabel))
            Text("No courses found for \"\(courseStore.searchText)\"")
                .font(.custom("Baskerville", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }
}
