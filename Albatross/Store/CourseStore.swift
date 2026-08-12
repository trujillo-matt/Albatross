import Foundation
import Combine

@MainActor
final class CourseStore: ObservableObject {
    @Published private(set) var allCourses: [Course] = []

    /// Bound to the search field — debounced before filtering
    @Published var searchText: String = ""

    /// Debounced, filtered results — updated ~200ms after typing stops
    @Published private(set) var results: [Course] = []

    /// Courses flagged isPreloaded — shown in the "Suggested" section before any search query
    var preloadedCourses: [Course] {
        allCourses.filter { $0.isPreloaded }
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadBundle()
        setupSearch()
    }

    private func setupSearch() {
        $searchText
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .map { [weak self] query -> [Course] in
                guard let self else { return [] }
                let q = query.trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { return [] }
                return self.allCourses
                    .filter {
                        $0.name.localizedCaseInsensitiveContains(q) ||
                        $0.city.localizedCaseInsensitiveContains(q) ||
                        $0.state.localizedCaseInsensitiveContains(q)
                    }
                    .prefix(20)
                    .map { $0 }
            }
            .assign(to: &$results)
    }

    private func loadBundle() {
        guard let url = Bundle.main.url(forResource: "courses", withExtension: "json") else {
            print("CourseStore: courses.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            allCourses = try JSONDecoder().decode([Course].self, from: data)
        } catch {
            print("CourseStore: failed to decode courses.json — \(error)")
        }
    }
}
