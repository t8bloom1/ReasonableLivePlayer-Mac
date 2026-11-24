import XCTest
@testable import RLPCore

/// Builds a MIDI 1.0 channel voice message as a one-word UMP (message type 2).
private func ump(_ status: UInt8, _ data1: UInt8, _ data2: UInt8, group: UInt32 = 0) -> UInt32 {
    0x2000_0000 | (group << 24) | (UInt32(status) << 16) | (UInt32(data1) << 8) | UInt32(data2)
}

final class MidiTests: XCTestCase {
    /// A message matches only when it is a note-on (0x90) with the configured channel and
    /// note and a non-zero velocity. Randomized port of the original property test.
    func testNoteOnMatchesOnlyWhenChannelNoteAndVelocityAllMatch() {
        var rng = SystemRandomNumberGenerator()
        let types: [UInt8] = [0x80, 0x90, 0xA0, 0xB0, 0xC0, 0xD0, 0xE0]
        for _ in 0..<2000 {
            let configChannel = Int.random(in: 0...15, using: &rng)
            let configNote = Int.random(in: 0...127, using: &rng)
            let msgChannel = Bool.random(using: &rng) ? configChannel : Int.random(in: 0...15, using: &rng)
            let msgNote = Bool.random(using: &rng) ? configNote : Int.random(in: 0...127, using: &rng)
            let velocity = Int.random(in: 0...127, using: &rng)
            let type = types.randomElement(using: &rng)!

            let parsed = UMPParser.parse([ump(type | UInt8(msgChannel), UInt8(msgNote), UInt8(velocity))])
            XCTAssertEqual(parsed.count, 1)
            let expected = type == 0x90 && msgChannel == configChannel && msgNote == configNote && velocity > 0
            XCTAssertEqual(parsed[0].isNoteOn(channel: configChannel, note: configNote), expected)
        }
    }

    func testParsesNoteOnWord() {
        let messages = UMPParser.parse([0x2090_3C64])
        XCTAssertEqual(messages, [MidiMessage(status: 0x90, data1: 0x3C, data2: 0x64)])
        XCTAssertTrue(messages[0].isNoteOn(channel: 0, note: 60))
        XCTAssertFalse(messages[0].isNoteOn(channel: 1, note: 60))
        XCTAssertFalse(messages[0].isNoteOn(channel: 0, note: 61))
    }

    func testParsesChannelFromStatus() {
        let messages = UMPParser.parse([ump(0x95, 0, 1)])
        XCTAssertTrue(messages[0].isNoteOn(channel: 5, note: 0))
        XCTAssertFalse(messages[0].isNoteOn(channel: 0, note: 0))
    }

    func testUMPGroupIsIgnored() {
        for group: UInt32 in 0...15 {
            let messages = UMPParser.parse([ump(0x90, 0, 100, group: group)])
            XCTAssertTrue(messages[0].isNoteOn(channel: 0, note: 0), "group \(group)")
        }
    }

    func testNoteOnWithZeroVelocityIsNotAMatch() {
        let messages = UMPParser.parse([ump(0x90, 0, 0)])
        XCTAssertEqual(messages.count, 1)
        XCTAssertFalse(messages[0].isNoteOn(channel: 0, note: 0))
    }

    func testNoteOffIsNotAMatch() {
        let messages = UMPParser.parse([ump(0x80, 0, 64)])
        XCTAssertFalse(messages[0].isNoteOn(channel: 0, note: 0))
    }

    func testSeveralMessagesInOnePacket() {
        // The first message is not the trigger; the second is. The .NET version only looked
        // at the first message in a buffer and would have missed it.
        let messages = UMPParser.parse([ump(0xB0, 7, 100), ump(0x90, 0, 90)])
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[1].isNoteOn(channel: 0, note: 0))
    }

    func testProgramChangeParses() {
        let messages = UMPParser.parse([ump(0xC0, 5, 0), ump(0x90, 1, 1)])
        XCTAssertEqual(messages.map { $0.kind }, [0xC0, 0x90])
    }

    func testSkipsOtherMessageTypesWithoutLosingAlignment() {
        let words: [UInt32] = [
            0x0000_0000,                         // type 0 utility (NOOP), 1 word
            0x10F8_0000,                         // type 1 system real-time (clock), 1 word
            0x3004_0102, 0x0304_0000,            // type 3 SysEx7, 2 words
            0x4090_3C00, 0xFFFF_0000,            // type 4 MIDI 2.0 channel voice, 2 words
            0x5000_0000, 0, 0, 0,                // type 5 SysEx8, 4 words
            0x8000_0000, 0,                      // type 8 reserved, 2 words
            0xB000_0000, 0, 0,                   // type B reserved, 3 words
            0xF000_0000, 0, 0, 0,                // type F UMP stream, 4 words
            ump(0x90, 9, 9),                     // the only message we want
        ]
        XCTAssertEqual(UMPParser.parse(words), [MidiMessage(status: 0x90, data1: 9, data2: 9)])
    }

    func testIgnoresNonChannelStatusInTypeTwoWord() {
        // Status 0xF8 is not a channel voice message; 0x10 has no high bit.
        XCTAssertEqual(UMPParser.parse([ump(0xF8, 0, 0), ump(0x10, 0, 0)]), [])
    }

    func testDataBytesAreMaskedToSevenBits() {
        let messages = UMPParser.parse([ump(0x90, 0xBC, 0xE4)])
        XCTAssertEqual(messages, [MidiMessage(status: 0x90, data1: 0x3C, data2: 0x64)])
    }

    func testTruncatedAndEmptyInputTerminates() {
        XCTAssertEqual(UMPParser.parse([]), [])
        XCTAssertEqual(UMPParser.parse([0x3000_0000]), [])                       // needs 2 words
        XCTAssertEqual(UMPParser.parse([0x5000_0000, 0, 0]), [])                 // needs 4 words
        XCTAssertEqual(UMPParser.parse([ump(0x90, 1, 1), 0x4090_0000]).count, 1) // trailing partial

        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let words = (0..<Int.random(in: 0...40, using: &rng)).map { _ in UInt32.random(in: 0...UInt32.max, using: &rng) }
            _ = UMPParser.parse(words)   // must return
        }
    }
}
