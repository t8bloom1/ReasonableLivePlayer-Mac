import Foundation

/// A MIDI channel voice message.
public struct MidiMessage: Equatable {
    public var status: UInt8
    public var data1: UInt8
    public var data2: UInt8

    public init(status: UInt8, data1: UInt8, data2: UInt8) {
        self.status = status
        self.data1 = data1
        self.data2 = data2
    }

    public var kind: UInt8 { status & 0xF0 }
    public var channel: Int { Int(status & 0x0F) }

    /// True for a note-on with non-zero velocity on `channel` (0-15) and `note` (0-127).
    /// A note-on with velocity 0 is a note-off and does not match.
    public func isNoteOn(channel: Int, note: Int) -> Bool {
        kind == 0x90 && self.channel == channel && Int(data1) == note && data2 > 0
    }
}

public enum MidiParser {
    /// Splits a raw MIDI byte buffer into channel messages. Handles several messages in
    /// one buffer, running status, interleaved real-time bytes and SysEx (which is skipped).
    /// Malformed input is skipped; this never loops forever.
    public static func parse(_ bytes: [UInt8]) -> [MidiMessage] {
        var messages: [MidiMessage] = []
        var running: UInt8 = 0
        var i = 0
        let n = bytes.count

        while i < n {
            let b = bytes[i]

            if b >= 0xF8 {                       // real-time: ignore, keeps running status
                i += 1
                continue
            }
            if b >= 0xF0 {                       // system common / SysEx: cancels running status
                running = 0
                i += 1
                if b == 0xF0 {
                    while i < n && bytes[i] != 0xF7 { i += 1 }
                    if i < n { i += 1 }          // consume EOX
                } else if b == 0xF1 || b == 0xF3 {
                    i += 1
                } else if b == 0xF2 {
                    i += 2
                }
                continue
            }

            var status = running
            if b & 0x80 != 0 {
                status = b
                running = b
                i += 1
            } else if running == 0 {             // data byte with no status: drop
                i += 1
                continue
            }

            let kind = status & 0xF0
            let dataLength = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
            guard i + dataLength <= n else { break }

            let d1 = bytes[i]
            let d2: UInt8 = dataLength == 2 ? bytes[i + 1] : 0
            if d1 & 0x80 != 0 { continue }       // next loop treats it as a new status byte
            if dataLength == 2 && d2 & 0x80 != 0 {
                i += 1                           // skip d1, next loop treats d2 as a status byte
                continue
            }

            messages.append(MidiMessage(status: status, data1: d1, data2: d2))
            i += dataLength
        }
        return messages
    }
}

public enum MidiNoteMatcher {
    /// Matches a packed message (`status | note << 8 | velocity << 16`) against a channel
    /// (0-15) and note (0-127). Same contract as the original `IsMatchingNoteOn`.
    public static func isMatchingNoteOn(midiData: Int, channel: Int, noteNumber: Int) -> Bool {
        let status = midiData & 0xFF
        let note = (midiData >> 8) & 0x7F
        let velocity = (midiData >> 16) & 0x7F
        return (status & 0xF0) == 0x90
            && (status & 0x0F) == channel
            && note == noteNumber
            && velocity > 0
    }
}
