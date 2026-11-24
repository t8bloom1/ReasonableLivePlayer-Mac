import XCTest
@testable import RLPCore

final class MidiTests: XCTestCase {
    /// Port of the property test: a packed message matches only when it is a note-on
    /// (0x90) with the configured channel and note and a non-zero velocity.
    func testPackedNoteOnMatchesOnlyWhenAllFieldsMatch() {
        var rng = SystemRandomNumberGenerator()
        let types = [0x80, 0x90, 0xA0, 0xB0, 0xC0, 0xD0, 0xE0]
        for _ in 0..<2000 {
            let configChannel = Int.random(in: 0...15, using: &rng)
            let configNote = Int.random(in: 0...127, using: &rng)
            let msgChannel = Bool.random(using: &rng) ? configChannel : Int.random(in: 0...15, using: &rng)
            let msgNote = Bool.random(using: &rng) ? configNote : Int.random(in: 0...127, using: &rng)
            let velocity = Int.random(in: 0...127, using: &rng)
            let type = types.randomElement(using: &rng)!
            let data = (type | msgChannel) | (msgNote << 8) | (velocity << 16)

            let expected = type == 0x90 && msgChannel == configChannel && msgNote == configNote && velocity > 0
            XCTAssertEqual(
                MidiNoteMatcher.isMatchingNoteOn(midiData: data, channel: configChannel, noteNumber: configNote),
                expected)
        }
    }

    func testParsesSingleNoteOn() {
        let messages = MidiParser.parse([0x90, 60, 100])
        XCTAssertEqual(messages, [MidiMessage(status: 0x90, data1: 60, data2: 100)])
        XCTAssertTrue(messages[0].isNoteOn(channel: 0, note: 60))
        XCTAssertFalse(messages[0].isNoteOn(channel: 1, note: 60))
        XCTAssertFalse(messages[0].isNoteOn(channel: 0, note: 61))
    }

    func testNoteOnWithZeroVelocityIsNotAMatch() {
        let messages = MidiParser.parse([0x90, 0, 0])
        XCTAssertEqual(messages.count, 1)
        XCTAssertFalse(messages[0].isNoteOn(channel: 0, note: 0))
    }

    func testNoteOffIsNotAMatch() {
        let messages = MidiParser.parse([0x80, 0, 64])
        XCTAssertFalse(messages[0].isNoteOn(channel: 0, note: 0))
    }

    func testParsesSeveralMessagesInOneBuffer() {
        // The first message is not the trigger; the second is. The .NET version only
        // looked at the first three bytes and would have missed it.
        let messages = MidiParser.parse([0xB0, 7, 100, 0x90, 0, 90])
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[1].isNoteOn(channel: 0, note: 0))
    }

    func testRunningStatus() {
        let messages = MidiParser.parse([0x91, 10, 100, 11, 100, 12, 0])
        XCTAssertEqual(messages.map { $0.data1 }, [10, 11, 12])
        XCTAssertEqual(messages.map { $0.status }, [0x91, 0x91, 0x91])
    }

    func testRealTimeBytesAreIgnored() {
        let messages = MidiParser.parse([0xF8, 0x90, 0xF8, 5, 100, 0xFE])
        XCTAssertEqual(messages, [MidiMessage(status: 0x90, data1: 5, data2: 100)])
    }

    func testSysExIsSkipped() {
        let messages = MidiParser.parse([0xF0, 1, 2, 3, 0xF7, 0x90, 9, 9])
        XCTAssertEqual(messages, [MidiMessage(status: 0x90, data1: 9, data2: 9)])
    }

    func testProgramChangeHasOneDataByte() {
        let messages = MidiParser.parse([0xC0, 5, 0x90, 1, 1])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].kind, 0xC0)
        XCTAssertEqual(messages[1].kind, 0x90)
    }

    func testMalformedAndTruncatedInputTerminates() {
        XCTAssertEqual(MidiParser.parse([]), [])
        XCTAssertEqual(MidiParser.parse([0x90]), [])
        XCTAssertEqual(MidiParser.parse([0x90, 60]), [])
        XCTAssertEqual(MidiParser.parse([60, 100]), [])            // data bytes with no status
        // A status byte in the middle of a message restarts parsing.
        XCTAssertEqual(MidiParser.parse([0x90, 60, 0x90, 61, 100]),
                       [MidiMessage(status: 0x90, data1: 61, data2: 100)])

        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let bytes = (0..<Int.random(in: 0...40, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
            _ = MidiParser.parse(bytes)   // must return
        }
    }
}
