import CoreMIDI
import Foundation

/// Listens on one CoreMIDI source for a note-on that matches a channel and note number.
///
/// Threading: `onTrigger` is called on a CoreMIDI thread. `onDevicesChanged` is called on
/// the thread that created the listener (CoreMIDI delivers setup notifications to the run
/// loop of the thread that created the client, which is the main thread in the app).
/// `connect`, `disconnect` and `verifyConnection` must be called from one thread (main).
public final class MidiNoteListener {
    public struct Source {
        public let endpoint: MIDIEndpointRef
        public let displayName: String   // e.g. "IAC Driver Bus 1"
        public let name: String          // e.g. "Bus 1"
    }

    public private(set) var isConnected = false
    public private(set) var deviceName: String?

    /// Called when a matching note-on arrives. Runs on a CoreMIDI thread.
    public var onTrigger: (() -> Void)?
    /// Called when `isConnected` changes. Runs on the caller's thread.
    public var onConnectionChanged: ((Bool) -> Void)?
    /// Called when the MIDI setup changes (device added, removed, taken online/offline).
    public var onDevicesChanged: (() -> Void)?

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var source = MIDIEndpointRef()

    public init() {
        MIDIClientCreateWithBlock("ReasonableLivePlayer" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                self?.onDevicesChanged?()
            }
        }
    }

    deinit {
        disconnect()
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: - Device discovery

    public static func sources() -> [Source] {
        (0..<MIDIGetNumberOfSources()).compactMap { index in
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { return nil }
            let display = stringProperty(endpoint, kMIDIPropertyDisplayName)
            let plain = stringProperty(endpoint, kMIDIPropertyName)
            guard let label = display ?? plain else { return nil }
            return Source(endpoint: endpoint, displayName: label, name: plain ?? label)
        }
    }

    /// Display names of all available inputs, for the settings picker.
    public static func availableDevices() -> [String] {
        sources().map { $0.displayName }
    }

    /// Finds a source by saved name. Matches the display name first, then the plain
    /// endpoint name, then a display-name prefix (so a saved "IAC Driver" still finds
    /// "IAC Driver Bus 1"). Case-insensitive.
    public static func findSource(named saved: String) -> Source? {
        let all = sources()
        func eq(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
        return all.first { eq($0.displayName, saved) }
            ?? all.first { eq($0.name, saved) }
            ?? all.first { $0.displayName.lowercased().hasPrefix(saved.lowercased()) }
    }

    private static func stringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr,
              let cf = value?.takeRetainedValue() else { return nil }
        return cf as String
    }

    // MARK: - Connection

    /// Connects to the named device. `channel` is 0-15, `noteNumber` 0-127.
    @discardableResult
    public func connect(deviceName name: String, channel: Int, noteNumber: Int) -> Bool {
        disconnect()
        deviceName = name

        guard client != 0, let found = Self.findSource(named: name) else {
            RLPLog.info("MIDI source \"\(name)\" not found")
            setConnected(false)
            return false
        }

        var newPort = MIDIPortRef()
        // Ask for the MIDI 1.0 protocol: CoreMIDI translates anything newer, so channel voice
        // messages arrive as single-word UMPs.
        let created = MIDIInputPortCreateWithProtocol(
            client, "ReasonableLivePlayer Input" as CFString, ._1_0, &newPort
        ) { [weak self] eventList, _ in
            for words in Self.packetWords(eventList) {
                for message in UMPParser.parse(words)
                where message.isNoteOn(channel: channel, note: noteNumber) {
                    self?.onTrigger?()
                }
            }
        }
        guard created == noErr else {
            setConnected(false)
            return false
        }

        guard MIDIPortConnectSource(newPort, found.endpoint, nil) == noErr else {
            MIDIPortDispose(newPort)
            setConnected(false)
            return false
        }

        port = newPort
        source = found.endpoint
        RLPLog.info("MIDI connected to \"\(found.displayName)\", channel \(channel + 1), note \(noteNumber)")
        setConnected(true)
        return true
    }

    public func disconnect() {
        if port != 0 {
            if source != 0 { MIDIPortDisconnectSource(port, source) }
            MIDIPortDispose(port)
        }
        port = 0
        source = 0
        setConnected(false)
    }

    /// Drops the connection if its source has disappeared (device unplugged or taken offline).
    public func verifyConnection() {
        guard isConnected else { return }
        let stillPresent = Self.sources().contains { $0.endpoint == source }
        if !stillPresent { disconnect() }
    }

    private func setConnected(_ value: Bool) {
        guard isConnected != value else { return }
        isConnected = value
        onConnectionChanged?(value)
    }

    // MARK: - Packet decoding

    /// Copies the UMP words of each packet in a `MIDIEventList`. Walks the list with
    /// `MIDIEventPacketNext` over the original memory, never over a copy, and reads with
    /// unaligned loads because CoreMIDI packs these structures.
    private static func packetWords(_ list: UnsafePointer<MIDIEventList>) -> [[UInt32]] {
        var result: [[UInt32]] = []
        let count = Int(list.pointee.numPackets)
        guard count > 0,
              let packetOffset = MemoryLayout<MIDIEventList>.offset(of: \MIDIEventList.packet),
              let countOffset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.wordCount),
              let wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words)
        else { return result }

        var current = UnsafeRawPointer(list).advanced(by: packetOffset).assumingMemoryBound(to: MIDIEventPacket.self)
        for _ in 0..<count {
            let raw = UnsafeRawPointer(current)
            let wordCount = min(64, Int(raw.loadUnaligned(fromByteOffset: countOffset, as: UInt32.self)))
            var words: [UInt32] = []
            words.reserveCapacity(wordCount)
            for index in 0..<wordCount {
                words.append(raw.loadUnaligned(fromByteOffset: wordsOffset + index * 4, as: UInt32.self))
            }
            result.append(words)
            current = UnsafePointer(MIDIEventPacketNext(current))
        }
        return result
    }
}
