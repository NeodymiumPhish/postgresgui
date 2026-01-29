//
//  DebugLog.swift
//  PostgresGUI
//
//  Conditional logging utility that only logs in Debug builds
//

import Foundation
import Logging

/// Utility for conditional debug logging
/// All logs are suppressed in Release builds for performance and privacy
enum DebugLog {
#if DEBUG
    // Log directory path. If empty, file logging is disabled.
    // If set, logs will be written to this directory/Logs/ with a new file created on each app run.
    // Logs are never deleted - each run creates a new timestamped log file.
    private static let logDirectory: String = ""
    
    private static var isLoggingConfigured = false
    private static let loggingQueue = DispatchQueue(label: "com.postgresgui.debuglog", qos: .utility)
    private static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    private static let filenameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    static func configureLogging() {
        guard !isLoggingConfigured else { return }
        isLoggingConfigured = true
        
        // If logDirectory is empty, skip file logging
        guard !logDirectory.isEmpty else { return }
        
        let logFileURL = makeLogFileURL()
        Swift.print("📝 Debug logs will be written to: \(logFileURL.path)")
        LoggingSystem.bootstrap { label in
            DebugFileLogHandler(
                label: label,
                logFileURL: logFileURL,
                queue: loggingQueue
            )
        }
    }
#endif
    
    /// Print a message only in Debug builds
    /// - Parameter items: Items to print (same signature as Swift's print)
    static func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        #if DEBUG
        Swift.print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
        #endif
    }
}

/// Extension to configure Logger instances for conditional logging
extension Logger {
    /// Create a logger that respects build configuration
    /// In Release builds, the logger will be configured to suppress most logs
    /// - Parameter label: Logger label
    /// - Returns: Configured Logger instance
    nonisolated static func debugLogger(label: String) -> Logger {
        #if DEBUG
        return Logger(label: label)
        #else
        // In Release builds, create a logger with critical log level
        // This suppresses info, debug, trace, and notice logs
        var logger = Logger(label: label)
        logger.logLevel = .critical
        return logger
        #endif
    }
}

#if DEBUG
private struct DebugFileLogHandler: LogHandler {
    let label: String
    var logLevel: Logger.Level = .debug
    var metadata: Logger.Metadata = [:]

    private let fileHandle: FileHandle?
    private let queue: DispatchQueue

    init(label: String, logFileURL: URL, queue: DispatchQueue) {
        self.label = label
        self.queue = queue

        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        self.fileHandle = try? FileHandle(forWritingTo: logFileURL)
    }

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let combinedMetadata = self.metadata.merging(metadata ?? [:], uniquingKeysWith: { _, new in new })
        let metadataString = combinedMetadata.isEmpty
            ? ""
            : " " + combinedMetadata.map { "\($0)=\($1)" }.joined(separator: " ")

        queue.async {
            let timestamp = DebugLog.localTimestamp()
            let lineText = "\(timestamp) [\(level)] \(label): \(message)\(metadataString)\n"
            guard let data = lineText.data(using: .utf8), let handle = fileHandle else { return }
            try? handle.write(contentsOf: data)
        }
    }
}

private extension DebugLog {
    static func localTimestamp() -> String {
        logTimestampFormatter.string(from: Date())
    }

    static func makeLogFileURL() -> URL {
        let logsDir = URL(fileURLWithPath: logDirectory, isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        
        let filename = "postgresgui-\(filenameTimestampFormatter.string(from: Date())).log"
        return logsDir.appendingPathComponent(filename)
    }
}
#endif
