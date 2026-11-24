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

/// Reads Universal MIDI Packet (UMP) words, the format CoreMIDI's current API delivers.
///
/// The app asks CoreMIDI for the MIDI 1.0 protocol, so channel voice messages arrive as
/// single 32-bit words (message type 2): `0x2 | group | status | data1 | data2`. CoreMIDI
/// translates MIDI 2.0 devices down to that form. Every other message type is skipped, using
/// its size from the UMP specification so the words after it stay aligned.
public enum UMPParser {
    /// Size in 32-bit words of a UMP whose first word has this message type (top nibble).
    static func wordCount(forMessageType type: UInt32) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4                 // 0x5, 0xD, 0xE, 0xF
        }
    }

    /// Extracts the MIDI 1.0 channel voice messages from a packet's words. The UMP group
    /// (virtual cable) is ignored. A truncated trailing message is dropped.
    public static func parse(_ words: [UInt32]) -> [MidiMessage] {
        var messages: [MidiMessage] = []
        var i = 0
        while i < words.count {
            let word = words[i]
            let type = word >> 28
            let size = wordCount(forMessageType: type)
            guard i + size <= words.count else { break }

            if type == 0x2 {
                let status = UInt8((word >> 16) & 0xFF)
                if status >= 0x80 && status < 0xF0 {
                    messages.append(MidiMessage(
                        status: status,
                        data1: UInt8((word >> 8) & 0x7F),
                        data2: UInt8(word & 0x7F)))
                }
            }
            i += size
        }
        return messages
    }
}
