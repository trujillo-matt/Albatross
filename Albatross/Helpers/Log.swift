import OSLog

/// One place for diagnostics. Messages go to the unified log, where Console and Xcode can filter them,
/// and values interpolated into them are redacted in release builds.
enum Log {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TrujSoft.Albatross", category: "app")
}
