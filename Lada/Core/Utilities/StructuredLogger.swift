import Foundation
import os

public enum LogLevel: String, Codable, Sendable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public struct LogEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let subsystem: String
    public let correlationID: String?
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        subsystem: String,
        correlationID: String? = nil,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.subsystem = subsystem
        self.correlationID = correlationID
        self.message = SecretRedactor.redact(message)
    }

    public var formattedLine: String {
        let iso = ISO8601DateFormatter().string(from: timestamp)
        let corr = correlationID.map { " [\($0)]" } ?? ""
        return "\(iso) [\(level.rawValue)] [\(subsystem)]\(corr) \(message)"
    }
}

public final class StructuredLogger: @unchecked Sendable {
    public static let shared = StructuredLogger()

    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private let maxEntries = 2000
    private let osLogger = Logger(subsystem: "com.lada.desktop", category: "general")

    public init() {}

    public func log(
        _ level: LogLevel,
        subsystem: String,
        correlationID: String? = nil,
        _ message: String
    ) {
        let entry = LogEntry(
            level: level,
            subsystem: subsystem,
            correlationID: correlationID,
            message: message
        )
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()

        switch level {
        case .debug:
            osLogger.debug("[\(subsystem, privacy: .public)] \(entry.message, privacy: .public)")
        case .info:
            osLogger.info("[\(subsystem, privacy: .public)] \(entry.message, privacy: .public)")
        case .warning:
            osLogger.warning("[\(subsystem, privacy: .public)] \(entry.message, privacy: .public)")
        case .error:
            osLogger.error("[\(subsystem, privacy: .public)] \(entry.message, privacy: .public)")
        }
    }

    public func recentEntries(limit: Int = 500) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        if entries.count <= limit {
            return entries
        }
        return Array(entries.suffix(limit))
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    public func exportRedactedLogText() -> String {
        let snapshot = recentEntries(limit: maxEntries)
        let raw = snapshot.map(\.formattedLine).joined(separator: "\n")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return SecretRedactor.redact(raw.replacingOccurrences(of: home, with: "~"))
    }
}
