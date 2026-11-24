import AppKit
import ApplicationServices
import Foundation

/// Opens and closes song files in Reason.
public protocol ReasonControlling: AnyObject {
    func openSong(path: String) async
    func closeSong(path: String) async
}

/// Whether this process may use the Accessibility API.
public enum AccessibilityPermission {
    /// - Parameter prompt: when true and not yet trusted, macOS shows its permission dialog.
    public static func isTrusted(prompt: Bool = false) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Opens songs with the default app for the file type and closes the front Reason
/// document by choosing File > Close through the Accessibility API. If the menu item
/// cannot be found, it falls back to the same AppleScript the .NET version used.
public final class ReasonBridge: ReasonControlling {
    public init() {}

    public func openSong(path: String) async {
        let url = URL(fileURLWithPath: path)
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
        // Give Reason a moment to start loading the document.
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    public func closeSong(path: String) async {
        guard let reason = Self.findReason() else {
            RLPLog.error("Close skipped: Reason is not running")
            return
        }

        reason.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 300_000_000)

        switch Self.pressFileClose(pid: reason.processIdentifier) {
        case .pressed:
            RLPLog.info("Closed document with File > Close (Accessibility)")
        case .pressFailed:
            RLPLog.error("File > Close was found but pressing it failed (no document open?)")
        case .notFound:
            RLPLog.error("File > Close not found through Accessibility; using AppleScript fallback")
            Self.closeWithAppleScript()
        }
    }

    // MARK: - Finding Reason

    private static func findReason() -> NSRunningApplication? {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.first { app in
            if let id = app.bundleIdentifier, id == own { return false }
            if app.localizedName == "Reason" { return true }
            return app.bundleIdentifier?.hasPrefix("com.propellerheads.") == true
                && (app.localizedName ?? "").hasPrefix("Reason")
        }
    }

    // MARK: - Accessibility

    private enum PressResult { case pressed, pressFailed, notFound }

    private static func pressFileClose(pid: pid_t) -> PressResult {
        let app = AXUIElementCreateApplication(pid)
        guard let menuBar = element(app, kAXMenuBarAttribute),
              let fileItem = children(of: menuBar).first(where: { title(of: $0) == "File" }),
              let fileMenu = children(of: fileItem).first,
              let closeItem = children(of: fileMenu).first(where: { title(of: $0) == "Close" })
        else { return .notFound }

        return AXUIElementPerformAction(closeItem, kAXPressAction as CFString) == .success
            ? .pressed : .pressFailed
    }

    private static func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(el, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of el: AXUIElement) -> [AXUIElement] {
        (attribute(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func title(of el: AXUIElement) -> String? {
        attribute(el, kAXTitleAttribute) as? String
    }

    // MARK: - AppleScript fallback (same script as the .NET version)

    private static func closeWithAppleScript() {
        let script = """
        tell application "Reason" to activate
        delay 0.3
        tell application "System Events"
          tell process "Reason"
            click menu item "Close" of menu "File" of menu bar 1
          end tell
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]
        let input = Pipe()
        process.standardInput = input
        do {
            try process.run()
            input.fileHandleForWriting.write(Data(script.utf8))
            try? input.fileHandleForWriting.close()
        } catch {
            // Best effort, as in the original.
        }
    }
}
