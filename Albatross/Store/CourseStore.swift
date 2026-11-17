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

    /// Courses the user typed in themselves, kept on the phone so they turn up in search next time.
    private static var customCoursesURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("customCourses.json")
    }

    init() {
        loadBundle()
        loadCustomCourses()
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

    /// Saves a course entered by hand. A course with the same name is kept as it is.
    @discardableResult
    func addCustomCourse(name: String, pars: [Int]) -> Course? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, pars.count == 18 else { return nil }
        if let existing = allCourses.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let course = Course(
            id: "custom-\(UUID().uuidString)",
            name: trimmed,
            city: "",
            state: "",
            isPreloaded: false,
            holes: pars.enumerated().map { index, par in
                CourseHole(number: index + 1, par: par, handicap: index + 1, yardage: 0)
            }
        )
        allCourses.insert(course, at: 0)
        saveCustomCourses()
        return course
    }

    private func loadCustomCourses() {
        guard let data = try? Data(contentsOf: Self.customCoursesURL),
              let courses = try? JSONDecoder().decode([Course].self, from: data) else { return }
        allCourses.insert(contentsOf: courses, at: 0)
    }

    private func saveCustomCourses() {
        let custom = allCourses.filter { $0.id.hasPrefix("custom-") }
        do {
            try JSONEncoder().encode(custom).write(to: Self.customCoursesURL, options: .atomic)
        } catch {
            print("CourseStore: failed to save custom courses — \(error)")
        }
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
