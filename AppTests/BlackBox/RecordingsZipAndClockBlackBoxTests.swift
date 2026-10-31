import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// A transport that answers every request with the same zip archive.
nonisolated struct RecordingArchiveTransport: HTTPTransport {
    let archive: Data

    func send(_ request: HTTPRequest) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200, body: archive, request: request,
            headers: ["Content-Type": "application/zip"])
    }
}

@Suite("StoredZip CRC-32")
struct BlackBoxZipCRCTests {
    @Test(
        "CRC-32 check values",
        arguments: [
            ("", 0x0000_0000), ("123456789", 0xCBF4_3926), ("a", 0xE8B7_BE43),
            ("The quick brown fox jumps over the lazy dog", 0x414F_A339),
        ] as [(String, UInt32)])
    func checkValues(text: String, crc: UInt32) {
        #expect(StoredZip.crc32(RecordingBytes.ascii(text)) == crc)
    }

    @Test("Matches the reference CRC-32 on random bytes", arguments: 0..<24)
    func reference(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed) + 2000)
        let bytes = random.bytes(random.int(0...2000))
        #expect(StoredZip.crc32(bytes) == RecordingChecksum.crc32(bytes))
    }

    @Test("Bytes followed by their CRC-32 leave the CRC-32 residue", arguments: 0..<12)
    func residue(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed) + 3000)
        let bytes = random.bytes(random.int(0...500))
        let crc = StoredZip.crc32(bytes)
        #expect(StoredZip.crc32(bytes + RecordingBytes.encode(UInt64(crc), size: 4)) == 0x2144_DF1C)
    }
}

@Suite("StoredZip archives")
struct BlackBoxStoredZipTests {
    nonisolated static func contents() -> [(String, [UInt8])] {
        var random = RecordingRandom(seed: 4000)
        return [
            ("activity.fit", []), ("1.fit", [0x2A]),
            ("21087654321_ACTIVITY.fit", random.bytes(5000)),
            ("Läufe am Morgen.fit", random.bytes(300)), ("long.bin", random.bytes(70_000)),
        ]
    }

    @Test("Local header, data, central directory and end record", arguments: contents())
    func structure(name: String, content: [UInt8]) throws {
        let zip = [UInt8](StoredZip.archive(name: name, content: Data(content)))
        let nameBytes = Array(name.utf8)
        let crc = RecordingChecksum.crc32(content)
        // Local file header.
        try #require(zip.count >= 30 + nameBytes.count + content.count + 46 + nameBytes.count + 22)
        #expect(RecordingBytes.uint32(zip, at: 0) == 0x0403_4B50)
        let flags = RecordingBytes.uint16(zip, at: 6)
        #expect(RecordingBytes.uint16(zip, at: 8) == 0, "stored, not compressed")
        if flags & 0x08 == 0 {
            #expect(RecordingBytes.uint32(zip, at: 14) == crc)
            #expect(RecordingBytes.uint32(zip, at: 18) == UInt32(content.count))
            #expect(RecordingBytes.uint32(zip, at: 22) == UInt32(content.count))
        }
        let localName = RecordingBytes.uint16(zip, at: 26)
        let localExtra = RecordingBytes.uint16(zip, at: 28)
        #expect(localName == nameBytes.count)
        #expect(Array(zip[30..<30 + localName]) == nameBytes)
        let dataStart = 30 + localName + localExtra
        #expect(Array(zip[dataStart..<dataStart + content.count]) == content)
        // End of central directory, without a comment.
        let end = zip.count - 22
        #expect(RecordingBytes.uint32(zip, at: end) == 0x0605_4B50)
        #expect(RecordingBytes.uint16(zip, at: end + 4) == 0)
        #expect(RecordingBytes.uint16(zip, at: end + 8) == 1)
        #expect(RecordingBytes.uint16(zip, at: end + 10) == 1)
        let directorySize = Int(RecordingBytes.uint32(zip, at: end + 12))
        let directory = Int(RecordingBytes.uint32(zip, at: end + 16))
        #expect(RecordingBytes.uint16(zip, at: end + 20) == 0)
        #expect(directory + directorySize == end)
        #expect(directory >= dataStart + content.count)
        // Central directory header.
        try #require(directory + 46 <= end)
        #expect(RecordingBytes.uint32(zip, at: directory) == 0x0201_4B50)
        #expect(RecordingBytes.uint16(zip, at: directory + 10) == 0)
        #expect(RecordingBytes.uint32(zip, at: directory + 16) == crc)
        #expect(RecordingBytes.uint32(zip, at: directory + 20) == UInt32(content.count))
        #expect(RecordingBytes.uint32(zip, at: directory + 24) == UInt32(content.count))
        let centralName = RecordingBytes.uint16(zip, at: directory + 28)
        #expect(centralName == nameBytes.count)
        #expect(RecordingBytes.uint32(zip, at: directory + 42) == 0, "local header offset")
        #expect(Array(zip[directory + 46..<directory + 46 + centralName]) == nameBytes)
    }

    @Test("Garmin's client reads the archive back", arguments: contents())
    func readByTheClient(name: String, content: [UInt8]) async throws {
        let archive = StoredZip.archive(name: name, content: Data(content))
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let client = try GarminClient(
            accessToken: "token", transport: RecordingArchiveTransport(archive: archive),
            environment: ProcessEnvironment(variables: [:], homeDirectory: home))
        let file = try await client.downloadActivity(42)
        #expect(file.content == Data(content))
        #expect(file.filename == name)
    }

    @Test("Archiving is deterministic")
    func deterministic() {
        let content = Data(RecordingBytes.ascii("same content"))
        let first = StoredZip.archive(name: "a.fit", content: content)
        let second = StoredZip.archive(name: "a.fit", content: content)
        #expect(first == second)
    }
}

@Suite("TimerClock")
struct BlackBoxTimerClockTests {
    static let start = RecordingFixtures.start

    static func events(_ list: [(Double, Bool)]) -> [FITActivity.TimerEvent] {
        list.map { FITActivity.TimerEvent(time: start + $0, isStart: $1) }
    }

    /// Start at 0, stop at 100, start at 160, stop at 300, start at 400.
    static let twoPauses = TimerClock(
        start: start,
        events: events([(0, true), (100, false), (160, true), (300, false), (400, true)]))

    @Test("Without events timer time is wall-clock time")
    func noEvents() {
        let clock = TimerClock(start: Self.start, events: [])
        #expect(clock.pauses.isEmpty)
        #expect(clock.start == Self.start)
        for seconds in [0, 1, 59.5, 3600, 86_400] {
            #expect(clock.seconds(at: Self.start + seconds) == seconds)
        }
    }

    @Test("Pauses lie between a stop and the next start")
    func pauses() {
        #expect(Self.twoPauses.pauses == [100...160, 300...400])
    }

    @Test(
        "Timer time leaves out the pauses",
        arguments: [
            (0, 0), (50, 50), (99.5, 99.5), (100, 100), (130, 100), (159, 100), (160, 100),
            (200, 140), (300, 240), (350, 240), (400, 240), (450, 290), (1000, 840),
        ] as [(Double, Double)])
    func seconds(wall: Double, timer: Double) {
        #expect(abs(Self.twoPauses.seconds(at: Self.start + wall) - timer) < 1e-9)
    }

    @Test("A second stop does not move the pause's beginning")
    func repeatedStops() {
        let clock = TimerClock(
            start: Self.start,
            events: Self.events([(0, true), (100, false), (120, false), (160, true)]))
        #expect(clock.seconds(at: Self.start + 130) == 100)
        #expect(clock.seconds(at: Self.start + 200) == 140)
    }

    @Test("A second start adds no pause")
    func repeatedStarts() {
        let clock = TimerClock(
            start: Self.start,
            events: Self.events([(0, true), (50, true), (100, false), (160, true)]))
        #expect(clock.pauses == [100...160])
        #expect(clock.seconds(at: Self.start + 75) == 75)
        #expect(clock.seconds(at: Self.start + 200) == 140)
    }

    @Test("A stop without an earlier start still pauses")
    func stopFirst() {
        let clock = TimerClock(start: Self.start, events: Self.events([(100, false), (160, true)]))
        #expect(clock.pauses == [100...160])
        #expect(clock.seconds(at: Self.start + 200) == 140)
    }

    @Test("Random pauses match a model of the timer", arguments: 0..<20)
    func model(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed) + 5000)
        var time = Double(random.int(0...30))
        var list: [(Double, Bool)] = [(time, true)]
        var pauses: [ClosedRange<Double>] = []
        for _ in 0..<random.int(0...8) {
            time += Double(random.int(1...600))
            let stop = time
            time += Double(random.int(1...600))
            pauses.append(stop...time)
            list += [(stop, false), (time, true)]
        }
        let clock = TimerClock(start: Self.start, events: Self.events(list))
        #expect(clock.pauses == pauses)
        for _ in 0..<50 {
            let wall = random.double(0...(time + 600))
            let paused = pauses.map { max(0, min(wall, $0.upperBound) - $0.lowerBound) }
            #expect(abs(clock.seconds(at: Self.start + wall) - (wall - paused.reduce(0, +))) < 1e-6)
        }
    }

    @Test("Timer time never runs backwards or faster than the clock", arguments: 0..<12)
    func monotonic(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed) + 6000)
        var time = 0.0
        let list = (0..<random.int(0...12)).map { _ in
            time += Double(random.int(1...300))
            return (time, random.chance(0.5))
        }
        let clock = TimerClock(start: Self.start, events: Self.events(list))
        #expect(clock.seconds(at: Self.start) == 0)
        var previous = (wall: 0.0, timer: 0.0)
        for wall in stride(from: 0.5, through: time + 300, by: 7.25) {
            let timer = clock.seconds(at: Self.start + wall)
            #expect(timer >= previous.timer - 1e-9)
            #expect(timer - previous.timer <= wall - previous.wall + 1e-9)
            #expect(timer <= wall + 1e-9)
            previous = (wall, timer)
        }
        for pause in clock.pauses {
            #expect(pause.lowerBound >= 0)
            let inside = clock.seconds(at: Self.start + (pause.lowerBound + pause.upperBound) / 2)
            #expect(abs(inside - clock.seconds(at: Self.start + pause.lowerBound)) < 1e-9)
        }
    }
}
