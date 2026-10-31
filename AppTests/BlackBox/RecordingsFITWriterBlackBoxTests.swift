import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// One FIT base type: its number, size and invalid value, from the FIT protocol.
nonisolated struct RecordingBaseTypeCase: Sendable, CustomTestStringConvertible {
    let number: UInt8
    let size: Int
    let invalid: UInt64

    var testDescription: String { "base type \(number)" }
}

/// A raw value of a base type and the number it holds.
nonisolated struct RecordingBaseValueCase: Sendable, CustomTestStringConvertible {
    let type: UInt8
    let raw: UInt64
    let number: Double

    var testDescription: String { "base type \(type), raw \(raw)" }
}

@Suite("FITBaseType")
struct BlackBoxFITBaseTypeTests {
    nonisolated static let types = [
        RecordingBaseTypeCase(number: 0, size: 1, invalid: 0xFF),
        RecordingBaseTypeCase(number: 1, size: 1, invalid: 0x7F),
        RecordingBaseTypeCase(number: 2, size: 1, invalid: 0xFF),
        RecordingBaseTypeCase(number: 3, size: 2, invalid: 0x7FFF),
        RecordingBaseTypeCase(number: 4, size: 2, invalid: 0xFFFF),
        RecordingBaseTypeCase(number: 5, size: 4, invalid: 0x7FFF_FFFF),
        RecordingBaseTypeCase(number: 6, size: 4, invalid: 0xFFFF_FFFF),
        RecordingBaseTypeCase(number: 7, size: 1, invalid: 0x00),
        RecordingBaseTypeCase(number: 8, size: 4, invalid: 0xFFFF_FFFF),
        RecordingBaseTypeCase(number: 9, size: 8, invalid: 0xFFFF_FFFF_FFFF_FFFF),
        RecordingBaseTypeCase(number: 10, size: 1, invalid: 0x00),
        RecordingBaseTypeCase(number: 11, size: 2, invalid: 0x0000),
        RecordingBaseTypeCase(number: 12, size: 4, invalid: 0x0000_0000),
        RecordingBaseTypeCase(number: 13, size: 1, invalid: 0xFF),
        RecordingBaseTypeCase(number: 14, size: 8, invalid: 0x7FFF_FFFF_FFFF_FFFF),
        RecordingBaseTypeCase(number: 15, size: 8, invalid: 0xFFFF_FFFF_FFFF_FFFF),
        RecordingBaseTypeCase(number: 16, size: 8, invalid: 0),
    ]

    nonisolated static let values = [
        RecordingBaseValueCase(type: 0, raw: 4, number: 4),
        RecordingBaseValueCase(type: 0, raw: 254, number: 254),
        RecordingBaseValueCase(type: 1, raw: 5, number: 5),
        RecordingBaseValueCase(type: 1, raw: 0xFF, number: -1),
        RecordingBaseValueCase(type: 1, raw: 0x80, number: -128),
        RecordingBaseValueCase(type: 1, raw: 0x7E, number: 126),
        RecordingBaseValueCase(type: 2, raw: 0, number: 0),
        RecordingBaseValueCase(type: 2, raw: 254, number: 254),
        RecordingBaseValueCase(type: 3, raw: 0xFFFF, number: -1),
        RecordingBaseValueCase(type: 3, raw: 0x8000, number: -32_768),
        RecordingBaseValueCase(type: 3, raw: 0x7FFE, number: 32_766),
        RecordingBaseValueCase(type: 4, raw: 0, number: 0),
        RecordingBaseValueCase(type: 4, raw: 0xFFFE, number: 65_534),
        RecordingBaseValueCase(type: 5, raw: 0xFFFF_FFFF, number: -1),
        RecordingBaseValueCase(type: 5, raw: 0x8000_0000, number: -2_147_483_648),
        RecordingBaseValueCase(type: 5, raw: 123_456_789, number: 123_456_789),
        RecordingBaseValueCase(type: 6, raw: 0xFFFF_FFFE, number: 4_294_967_294),
        RecordingBaseValueCase(type: 6, raw: 1_000_000_000, number: 1_000_000_000),
        RecordingBaseValueCase(type: 8, raw: UInt64(Float(1.5).bitPattern), number: 1.5),
        RecordingBaseValueCase(type: 8, raw: UInt64(Float(-0.25).bitPattern), number: -0.25),
        RecordingBaseValueCase(type: 9, raw: Double(-12.25).bitPattern, number: -12.25),
        RecordingBaseValueCase(type: 9, raw: Double(6.0e23).bitPattern, number: 6.0e23),
        RecordingBaseValueCase(type: 10, raw: 1, number: 1),
        RecordingBaseValueCase(type: 10, raw: 0xFF, number: 255),
        RecordingBaseValueCase(type: 11, raw: 0xFFFF, number: 65_535),
        RecordingBaseValueCase(type: 12, raw: 0xFFFF_FFFF, number: 4_294_967_295),
        RecordingBaseValueCase(type: 13, raw: 0, number: 0),
        RecordingBaseValueCase(type: 13, raw: 0x7F, number: 127),
        RecordingBaseValueCase(type: 14, raw: 0xFFFF_FFFF_FFFF_FFFF, number: -1),
        RecordingBaseValueCase(type: 14, raw: 1 << 40, number: 1_099_511_627_776),
        RecordingBaseValueCase(type: 15, raw: 12_345, number: 12_345),
        RecordingBaseValueCase(type: 15, raw: 1 << 60, number: 1_152_921_504_606_846_976),
        RecordingBaseValueCase(type: 16, raw: 1, number: 1),
        RecordingBaseValueCase(type: 16, raw: 1 << 63, number: 9_223_372_036_854_775_808),
    ]

    @Test("Sizes by base type number", arguments: types)
    func size(type: RecordingBaseTypeCase) {
        #expect(FITBaseType.size(type.number) == type.size)
    }

    @Test("The invalid value is nil", arguments: types)
    func invalidValue(type: RecordingBaseTypeCase) {
        #expect(FITBaseType.value(type.invalid, type: type.number) == nil)
    }

    @Test("Valid raw values are their numbers", arguments: values)
    func validValue(value: RecordingBaseValueCase) {
        #expect(FITBaseType.value(value.raw, type: value.type) == value.number)
    }

    @Test("Strings have no number", arguments: [0x00, 0x30, 0x41, 0x7A, 0xFF, 0x4142] as [UInt64])
    func strings(raw: UInt64) {
        #expect(FITBaseType.value(raw, type: 7) == nil)
    }

    @Test("Unsigned values below the invalid one are numbers", arguments: [2, 4, 6, 15] as [UInt8])
    func unsignedRange(type: UInt8) {
        var random = RecordingRandom(seed: UInt64(type))
        let bits = 8 * FITBaseType.size(type)
        let invalid = bits == 64 ? UInt64.max : (UInt64(1) << bits) - 1
        for _ in 0..<200 {
            let raw = UInt64.random(in: 0..<invalid, using: &random)
            #expect(FITBaseType.value(raw, type: type) == Double(raw))
        }
    }
}

@Suite("FITWriter CRC")
struct BlackBoxFITCRCTests {
    @Test("CRC-16 of nothing is 0")
    func empty() {
        #expect(FITWriter.crc([]) == 0)
    }

    @Test("CRC-16/ARC check value of \"123_456_789\"")
    func checkValue() {
        #expect(FITWriter.crc(RecordingBytes.ascii("123456789")) == 0xBB3D)
    }

    @Test("Single bytes", arguments: [0x00, 0x01, 0x80, 0xFF] as [UInt8])
    func singleBytes(byte: UInt8) {
        #expect(FITWriter.crc([byte]) == RecordingChecksum.crc16([byte]))
    }

    @Test("Matches the reference CRC on random bytes", arguments: 0..<24)
    func reference(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed))
        let bytes = random.bytes(random.int(0...600))
        #expect(FITWriter.crc(bytes) == RecordingChecksum.crc16(bytes))
    }

    @Test("Bytes followed by their own CRC check to zero", arguments: 0..<24)
    func residue(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed) + 500)
        let bytes = random.bytes(random.int(0...400))
        let crc = FITWriter.crc(bytes)
        #expect(FITWriter.crc(bytes + RecordingBytes.encode(UInt64(crc), size: 2)) == 0)
    }

    @Test("A changed byte changes the CRC", arguments: 0..<12)
    func detectsChanges(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed) + 900)
        let bytes = random.bytes(random.int(1...200))
        var changed = bytes
        let index = random.int(0...(bytes.count - 1))
        changed[index] ^= UInt8(random.int(1...255))
        #expect(FITWriter.crc(changed) != FITWriter.crc(bytes))
    }
}

@Suite("FITWriter files")
struct BlackBoxFITWriterTests {
    static func checkFrame(_ bytes: [UInt8], sourceLocation: SourceLocation = #_sourceLocation) {
        guard bytes.count >= 14 else {
            Issue.record("only \(bytes.count) bytes", sourceLocation: sourceLocation)
            return
        }
        let headerSize = Int(bytes[0])
        #expect([12, 14].contains(headerSize), sourceLocation: sourceLocation)
        #expect([1, 2].contains(bytes[1] >> 4), "protocol version", sourceLocation: sourceLocation)
        #expect(
            Array(bytes[8..<12]) == RecordingBytes.ascii(".FIT"), sourceLocation: sourceLocation)
        let dataSize = Int(RecordingBytes.uint32(bytes, at: 4))
        #expect(headerSize + dataSize + 2 == bytes.count, sourceLocation: sourceLocation)
        if headerSize == 14 {
            let headerCRC = RecordingBytes.uint16(bytes, at: 12)
            let expected = Int(RecordingChecksum.crc16(Array(bytes[0..<12])))
            #expect(headerCRC == 0 || headerCRC == expected, sourceLocation: sourceLocation)
        }
        let trailer = RecordingBytes.uint16(bytes, at: bytes.count - 2)
        let content = Array(bytes.dropLast(2))
        #expect(trailer == Int(RecordingChecksum.crc16(content)), sourceLocation: sourceLocation)
        #expect(RecordingChecksum.crc16(bytes) == 0, sourceLocation: sourceLocation)
        #expect(FITWriter.crc(bytes) == 0, sourceLocation: sourceLocation)
    }

    static func expectSame(
        _ actual: FITActivity, _ expected: FITActivity,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(actual.records.count == expected.records.count, sourceLocation: sourceLocation)
        for (index, (got, want)) in zip(actual.records, expected.records).enumerated() {
            #expect(
                RecordingRoundTrip.same(got, want), "record \(index): \(got) vs \(want)",
                sourceLocation: sourceLocation)
        }
        #expect(actual.laps.count == expected.laps.count, sourceLocation: sourceLocation)
        for (index, (got, want)) in zip(actual.laps, expected.laps).enumerated() {
            #expect(
                RecordingRoundTrip.same(got, want), "lap \(index): \(got) vs \(want)",
                sourceLocation: sourceLocation)
        }
        #expect(actual.sets.count == expected.sets.count, sourceLocation: sourceLocation)
        for (index, (got, want)) in zip(actual.sets, expected.sets).enumerated() {
            #expect(
                RecordingRoundTrip.same(got, want), "set \(index): \(got) vs \(want)",
                sourceLocation: sourceLocation)
        }
        #expect(
            actual.timerEvents.map(\.isStart) == expected.timerEvents.map(\.isStart),
            sourceLocation: sourceLocation)
        #expect(
            actual.timerEvents.map(\.time) == expected.timerEvents.map(\.time),
            sourceLocation: sourceLocation)
    }

    @Test("An empty activity is a valid, empty FIT file")
    func emptyActivity() throws {
        let data = FITWriter.encode(FITActivity())
        Self.checkFrame([UInt8](data))
        let fit = try FITActivity(decoding: data)
        #expect(fit == FITActivity())
    }

    @Test("Header, data size and CRC are consistent", arguments: 0..<20)
    func frame(seed: Int) {
        Self.checkFrame(
            [UInt8](FITWriter.encode(RecordingFixtures.randomActivity(seed: UInt64(seed)))))
    }

    @Test("Random activities survive a round trip", arguments: 0..<30)
    func roundTrip(seed: Int) throws {
        let activity = RecordingFixtures.randomActivity(seed: UInt64(seed) + 10_000)
        let decoded = try FITActivity(decoding: FITWriter.encode(activity))
        Self.expectSame(decoded, activity)
    }

    @Test("Encoding is deterministic", arguments: 0..<5)
    func deterministic(seed: Int) {
        let activity = RecordingFixtures.randomActivity(seed: UInt64(seed))
        let first = FITWriter.encode(activity)
        let second = FITWriter.encode(activity)
        #expect(first == second)
    }

    @Test("Decoding and encoding again gives the same activity", arguments: 0..<10)
    func idempotent(seed: Int) throws {
        let activity = RecordingFixtures.randomActivity(seed: UInt64(seed) + 77)
        let once = try FITActivity(decoding: FITWriter.encode(activity))
        let twice = try FITActivity(decoding: FITWriter.encode(once))
        #expect(twice == once)
    }

    @Test("Only records, laps, sets or timer events")
    func singleKinds() throws {
        var random = RecordingRandom(seed: 4242)
        let parts = [
            FITActivity(records: RecordingFixtures.randomRecords(20, using: &random)),
            FITActivity(laps: RecordingFixtures.randomLaps(4, using: &random)),
            FITActivity(sets: RecordingFixtures.randomSets(6, using: &random)),
            FITActivity(timerEvents: RecordingFixtures.randomTimerEvents(5, using: &random)),
        ]
        for activity in parts {
            let data = FITWriter.encode(activity)
            Self.checkFrame([UInt8](data))
            Self.expectSame(try FITActivity(decoding: data), activity)
        }
    }

    @Test("Records with nothing but a time survive a round trip")
    func bareRecords() throws {
        let records = (0..<10).map {
            FITActivity.Record(time: RecordingFixtures.start + Double($0))
        }
        let decoded = try FITActivity(decoding: FITWriter.encode(FITActivity(records: records)))
        #expect(decoded.records == records)
    }

    @Test("Extreme but valid values survive a round trip")
    func extremes() throws {
        let record = FITActivity.Record(
            time: RecordingFixtures.start, latitude: RecordingFixtures.degrees(Int32.max - 1),
            longitude: RecordingFixtures.degrees(Int32.min + 1), altitude: -500, heartRate: 254,
            cadence: 254, distance: 42_949_672.94, speed: 65.534, power: 65_534)
        let lap = FITActivity.Lap(
            start: RecordingFixtures.start, elapsed: 0, moving: 0, distance: 0, averageSpeed: 0,
            averageHeartRate: 0, maxHeartRate: 254, ascent: 65_534, averagePower: 0)
        let set = FITActivity.ExerciseSet(
            start: RecordingFixtures.start, duration: 0, repetitions: 0, weight: 0,
            isActive: true, category: 0)
        let activity = FITActivity(records: [record], laps: [lap], sets: [set])
        Self.expectSame(try FITActivity(decoding: FITWriter.encode(activity)), activity)
    }

    @Test("Garmin's fractional cadence survives a round trip", arguments: 0..<5)
    func fractionalCadence(seed: Int) throws {
        var random = RecordingRandom(seed: UInt64(seed) + 20_000)
        let records = RecordingFixtures.randomRecords(100, using: &random, fractionalCadence: true)
        let decoded = try FITActivity(decoding: FITWriter.encode(FITActivity(records: records)))
        #expect(decoded.records.count == records.count)
        for (got, want) in zip(decoded.records, records) {
            #expect(
                RecordingFixtures.close(got.cadence, want.cadence, within: 1.0 / 256),
                "\(String(describing: got.cadence)) vs \(String(describing: want.cadence))")
        }
    }

    @Test("Many records survive a round trip")
    func manyRecords() throws {
        var random = RecordingRandom(seed: 8888)
        let activity = FITActivity(records: RecordingFixtures.randomRecords(20_000, using: &random))
        let data = FITWriter.encode(activity)
        Self.checkFrame([UInt8](data))
        Self.expectSame(try FITActivity(decoding: data), activity)
    }
}

/// The written messages, read with an independent parser, follow the FIT profile.
@Suite("FITWriter messages follow the FIT profile")
struct BlackBoxFITWriterProfileTests {
    static func parse(_ activity: FITActivity) throws -> RecordingFITFile {
        try RecordingFITFile([UInt8](FITWriter.encode(activity)))
    }

    static func expectField(
        _ message: RecordingFITMessage, _ numbers: [Int], _ expected: UInt64?, invalid: UInt64,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let values = numbers.compactMap { message.unsigned($0) }.filter { $0 != invalid }
        if let expected {
            #expect(!values.isEmpty, "fields \(numbers) missing", sourceLocation: sourceLocation)
            #expect(
                values.allSatisfy { $0 == expected }, "\(values) vs \(expected)",
                sourceLocation: sourceLocation)
        } else {
            #expect(
                values.isEmpty, "fields \(numbers) should be invalid",
                sourceLocation: sourceLocation)
        }
    }

    static func scaled(_ value: Double?, _ scale: Double, offset: Double = 0) -> UInt64? {
        value.map { UInt64((($0 + offset) * scale).rounded()) }
    }

    @Test("One record message (20) per record", arguments: 0..<10)
    func records(seed: Int) throws {
        let activity = RecordingFixtures.randomActivity(seed: UInt64(seed) + 300)
        let messages = try Self.parse(activity).messages(20)
        #expect(messages.count == activity.records.count)
        for (message, record) in zip(messages, activity.records) {
            #expect(message.timestamp == RecordingFixtures.fitSeconds(record.time))
            #expect(
                message.signed32(0).flatMap { $0 == Int32.max ? nil : $0 }
                    == record.latitude.map(RecordingFixtures.semicircles))
            #expect(
                message.signed32(1).flatMap { $0 == Int32.max ? nil : $0 }
                    == record.longitude.map(RecordingFixtures.semicircles))
            Self.expectField(message, [3], record.heartRate.map(UInt64.init), invalid: 0xFF)
            Self.expectField(message, [7], record.power.map(UInt64.init), invalid: 0xFFFF)
            Self.expectField(message, [5], Self.scaled(record.distance, 100), invalid: 0xFFFF_FFFF)
            Self.expectField(
                message, [6, 73], Self.scaled(record.speed, 1000),
                invalid: message.fields[6] != nil ? 0xFFFF : 0xFFFF_FFFF)
            Self.expectField(
                message, [2, 78], Self.scaled(record.altitude, 5, offset: 500),
                invalid: message.fields[2] != nil ? 0xFFFF : 0xFFFF_FFFF)
            Self.expectField(message, [4], record.cadence.map { UInt64($0) }, invalid: 0xFF)
        }
    }

    @Test("One lap message (19) per lap", arguments: 0..<10)
    func laps(seed: Int) throws {
        var random = RecordingRandom(seed: UInt64(seed) + 600)
        let laps = RecordingFixtures.randomLaps(6, using: &random)
        let messages = try Self.parse(FITActivity(laps: laps)).messages(19)
        #expect(messages.count == laps.count)
        for (message, lap) in zip(messages, laps) {
            let start = lap.start.map { UInt64(RecordingFixtures.fitSeconds($0)) }
            Self.expectField(message, [2], start, invalid: 0xFFFF_FFFF)
            Self.expectField(message, [7], Self.scaled(lap.elapsed, 1000), invalid: 0xFFFF_FFFF)
            Self.expectField(message, [8], Self.scaled(lap.moving, 1000), invalid: 0xFFFF_FFFF)
            Self.expectField(message, [9], Self.scaled(lap.distance, 100), invalid: 0xFFFF_FFFF)
            Self.expectField(
                message, [13, 110], Self.scaled(lap.averageSpeed, 1000),
                invalid: message.fields[13] != nil ? 0xFFFF : 0xFFFF_FFFF)
            Self.expectField(message, [15], lap.averageHeartRate.map(UInt64.init), invalid: 0xFF)
            Self.expectField(message, [16], lap.maxHeartRate.map(UInt64.init), invalid: 0xFF)
            Self.expectField(message, [21], lap.ascent.map(UInt64.init), invalid: 0xFFFF)
            Self.expectField(message, [19], lap.averagePower.map(UInt64.init), invalid: 0xFFFF)
        }
    }

    @Test("One set message (225) per strength set", arguments: 0..<10)
    func sets(seed: Int) throws {
        var random = RecordingRandom(seed: UInt64(seed) + 700)
        let sets = RecordingFixtures.randomSets(6, using: &random)
        let messages = try Self.parse(FITActivity(sets: sets)).messages(225)
        #expect(messages.count == sets.count)
        for (message, set) in zip(messages, sets) {
            let start = set.start.map { UInt64(RecordingFixtures.fitSeconds($0)) }
            Self.expectField(message, [6], start, invalid: 0xFFFF_FFFF)
            Self.expectField(message, [0], Self.scaled(set.duration, 1000), invalid: 0xFFFF_FFFF)
            Self.expectField(message, [3], set.repetitions.map(UInt64.init), invalid: 0xFFFF)
            Self.expectField(message, [4], Self.scaled(set.weight, 16), invalid: 0xFFFF)
            #expect(message.unsigned(5) == (set.isActive ? 1 : 0))
            let category = message.fields[7].map { RecordingBytes.decode($0.prefix(2)) }
            #expect((category == 0xFFFF ? nil : category) == set.category.map(UInt64.init))
        }
    }

    @Test("Timer events are timer starts and stops (event 21)", arguments: 0..<10)
    func timerEvents(seed: Int) throws {
        var random = RecordingRandom(seed: UInt64(seed) + 800)
        let events = RecordingFixtures.randomTimerEvents(7, using: &random)
        let messages = try Self.parse(FITActivity(timerEvents: events)).messages(21)
            .filter { $0.unsigned(0) == 0 }
        #expect(messages.count == events.count)
        for (message, event) in zip(messages, events) {
            #expect(message.timestamp == RecordingFixtures.fitSeconds(event.time))
            let type = try #require(message.unsigned(1))
            if event.isStart {
                #expect(type == 0)
            } else {
                #expect([1, 4, 8, 9].contains(type))
            }
        }
    }

    @Test("Every data message refers to a definition and fits the declared size")
    func wellFormed() throws {
        let file = try Self.parse(RecordingFixtures.randomActivity(seed: 5, records: 500))
        #expect(file.definitionCount >= 1)
        #expect(file.messages.count >= 500)
    }
}

/// Tolerant comparisons at FIT's resolution: half a unit of each field's scale.
nonisolated enum RecordingRoundTrip {
    static func sameTime(_ actual: Date?, _ expected: Date?) -> Bool {
        RecordingFixtures.close(
            actual?.timeIntervalSince1970, expected?.timeIntervalSince1970, within: 0.5)
    }

    static func same(_ actual: FITActivity.Record, _ expected: FITActivity.Record) -> Bool {
        sameTime(actual.time, expected.time)
            && RecordingFixtures.close(actual.latitude, expected.latitude, within: 4e-8)
            && RecordingFixtures.close(actual.longitude, expected.longitude, within: 4e-8)
            && RecordingFixtures.close(actual.altitude, expected.altitude, within: 0.1)
            && actual.heartRate == expected.heartRate
            && RecordingFixtures.close(actual.cadence, expected.cadence, within: 1.0 / 256)
            && RecordingFixtures.close(actual.distance, expected.distance, within: 0.005)
            && RecordingFixtures.close(actual.speed, expected.speed, within: 0.0005)
            && actual.power == expected.power
    }

    static func same(_ actual: FITActivity.Lap, _ expected: FITActivity.Lap) -> Bool {
        sameTime(actual.start, expected.start)
            && RecordingFixtures.close(actual.elapsed, expected.elapsed, within: 0.0005)
            && RecordingFixtures.close(actual.moving, expected.moving, within: 0.0005)
            && RecordingFixtures.close(actual.distance, expected.distance, within: 0.005)
            && RecordingFixtures.close(actual.averageSpeed, expected.averageSpeed, within: 0.0005)
            && actual.averageHeartRate == expected.averageHeartRate
            && actual.maxHeartRate == expected.maxHeartRate
            && actual.ascent == expected.ascent
            && actual.averagePower == expected.averagePower
    }

    static func same(
        _ actual: FITActivity.ExerciseSet, _ expected: FITActivity.ExerciseSet
    )
        -> Bool
    {
        sameTime(actual.start, expected.start)
            && RecordingFixtures.close(actual.duration, expected.duration, within: 0.0005)
            && actual.repetitions == expected.repetitions
            && RecordingFixtures.close(actual.weight, expected.weight, within: 1.0 / 32)
            && actual.isActive == expected.isActive
            && actual.category == expected.category
    }
}
