import Foundation
#if canImport(os)
import os
#endif

/// Application log. On macOS it writes to the unified log, so you can watch it in Console.app
/// (filter on subsystem `com.reasonablelive.player`) or with
/// `log stream --predicate 'subsystem == "com.reasonablelive.player"'`.
public enum RLPLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.reasonablelive.player", category: "app")
    public static func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    public static func error(_ message: String) { logger.error("\(message, privacy: .public)") }
    #else
    public static func info(_ message: String) {}
    public static func error(_ message: String) {}
    #endif
}

/// Keeps the Mac awake and exempts the app from App Nap while a set is running.
///
/// RLP usually sits behind Reason. Without this, macOS may coalesce its timers (including the
/// transition delay) or sleep the machine mid-set. The display is also kept on so the
/// playlist stays visible.
public final class ActivityKeeper {
    private var token: NSObjectProtocol?

    public init() {}

    public var isActive: Bool { token != nil }

    public func setActive(_ active: Bool, reason: String = "Playing a live set") {
        if active, token == nil {
            #if canImport(Darwin)
            token = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleDisplaySleepDisabled], reason: reason)
            #else
            token = NSObject()   // power assertions exist only on macOS; keeps tests portable
            #endif
            RLPLog.info("Keep-awake on")
        } else if !active, let current = token {
            #if canImport(Darwin)
            ProcessInfo.processInfo.endActivity(current)
            #endif
            token = nil
            RLPLog.info("Keep-awake off")
        }
    }

    deinit { setActive(false) }
}
