import OSLog

extension Logger {
    static func make(category: String) -> Logger {
        Logger(subsystem: "com.open-maestri.app", category: category)
    }
}
