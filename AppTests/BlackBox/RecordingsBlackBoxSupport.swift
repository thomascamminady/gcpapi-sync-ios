import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

// Helpers for the recordings black-box tests: a seeded random number generator, reference
// checksums, a byte-level FIT builder and parser written from the FIT protocol, and
// generators of activities whose values survive FIT's resolution exactly.

/// SplitMix64: a tiny deterministic generator, so every randomized test is reproducible.
nonisolated struct RecordingRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }

    mutating func bytes(_ count: Int) -> [UInt8] {
        (0..<count).map { _ in UInt8.random(in: 0...255, using: &self) }
    }
}

/// Little- and big-endian integers as bytes.
nonisolated enum RecordingBytes {
    static func encode(_ value: UInt64, size: Int, bigEndian: Bool = false) -> [UInt8] {
        let little = (0..<size).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
        return bigEndian ? Array(little.reversed()) : little
    }

    static func decode(_ bytes: ArraySlice<UInt8>, bigEndian: Bool = false) -> UInt64 {
        let ordered = bigEndian ? Array(bytes) : Array(bytes.reversed())
        return ordered.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    static func uint16(_ bytes: [UInt8], at offset: Int) -> Int {
        Int(decode(bytes[offset..<offset + 2]))
    }

    static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(decode(bytes[offset..<offset + 4]))
    }

    static func ascii(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    /// `text` as a fixed-size, NUL-padded FIT string field.
    static func string(_ text: String, size: Int) -> [UInt8] {
        let bytes = Array(text.utf8.prefix(size - 1))
        return bytes + [UInt8](repeating: 0, count: size - bytes.count)
    }
}

/// Bit-by-bit reference implementations of the published checksums.
nonisolated enum RecordingChecksum {
    /// CRC-16/ARC, the FIT CRC: reflected polynomial 0x8005 (0xA001), initial value 0.
    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    /// CRC-32/ISO-HDLC, the zip CRC: reflected polynomial 0x04C11DB7, inverted in and out.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

/// FIT base type bytes, as they appear in field definitions.
nonisolated enum RecordingBase {
    static let enumeration: UInt8 = 0x00
    static let sint8: UInt8 = 0x01
    static let uint8: UInt8 = 0x02
    static let sint16: UInt8 = 0x83
    static let uint16: UInt8 = 0x84
    static let sint32: UInt8 = 0x85
    static let uint32: UInt8 = 0x86
    static let string: UInt8 = 0x07
    static let float32: UInt8 = 0x88
    static let float64: UInt8 = 0x89
    static let uint8z: UInt8 = 0x0A
    static let uint16z: UInt8 = 0x8B
    static let uint32z: UInt8 = 0x8C
    static let byte: UInt8 = 0x0D
    static let sint64: UInt8 = 0x8E
    static let uint64: UInt8 = 0x8F
    static let uint64z: UInt8 = 0x90

    static func size(_ baseType: UInt8) -> Int {
        switch baseType & 0x1F {
        case 0, 1, 2, 7, 10, 13: 1
        case 3, 4, 11: 2
        case 5, 6, 8, 12: 4
        default: 8
        }
    }
}

/// One field of a FIT definition message. For developer fields `baseType` is the developer
/// data index, as in the protocol.
nonisolated struct RecordingFITField: Sendable {
    let number: UInt8
    let size: Int
    let baseType: UInt8

    init(_ number: UInt8, _ baseType: UInt8, size: Int? = nil) {
        self.number = number
        self.baseType = baseType
        self.size = size ?? RecordingBase.size(baseType)
    }
}

/// Builds FIT files byte by byte, as the FIT protocol describes them.
nonisolated struct RecordingFITBuilder {
    private struct Definition {
        let fields: [RecordingFITField]
        let bigEndian: Bool
    }

    private(set) var body: [UInt8] = []
    private var definitions: [UInt8: Definition] = [:]

    mutating func define(
        local: UInt8, global: UInt16, fields: [RecordingFITField],
        developer: [RecordingFITField] = []
    ) {
        define(local: local, global: global, bigEndian: false, fields: fields, developer: developer)
    }

    mutating func define(
        local: UInt8,
        global: UInt16,
        bigEndian: Bool,
        fields: [RecordingFITField],
        developer: [RecordingFITField] = []
    ) {
        body.append(0x40 | (developer.isEmpty ? 0 : 0x20) | local)
        body += [0, bigEndian ? 1 : 0]
        body += RecordingBytes.encode(UInt64(global), size: 2, bigEndian: bigEndian)
        body.append(UInt8(fields.count))
        for field in fields {
            body += [field.number, UInt8(field.size), field.baseType]
        }
        if !developer.isEmpty {
            body.append(UInt8(developer.count))
            for field in developer {
                body += [field.number, UInt8(field.size), field.baseType]
            }
        }
        definitions[local] = Definition(fields: fields, bigEndian: bigEndian)
    }

    /// A data message with one integer per field, in the definition's byte order.
    mutating func data(local: UInt8, _ values: [UInt64], developer: [UInt8] = []) {
        body.append(local & 0x0F)
        append(local: local, values: values, developer: developer)
    }

    /// A data message whose fields are given as raw bytes, for strings and arrays.
    mutating func data(local: UInt8, fields: [[UInt8]]) {
        body.append(local & 0x0F)
        body += fields.flatMap(\.self)
    }

    /// A data message with a compressed timestamp header.
    mutating func compressed(local: UInt8, offset: UInt8, _ values: [UInt64]) {
        body.append(0x80 | ((local & 0x03) << 5) | (offset & 0x1F))
        append(local: local, values: values, developer: [])
    }

    mutating func raw(_ bytes: [UInt8]) {
        body += bytes
    }

    /// A file_id message of an activity file on local message type `local`.
    mutating func fileID(local: UInt8 = 0, created: UInt32 = 1_000_000_000) {
        define(
            local: local, global: 0,
            fields: [
                RecordingFITField(0, RecordingBase.enumeration),
                RecordingFITField(1, RecordingBase.uint16),
                RecordingFITField(2, RecordingBase.uint16),
                RecordingFITField(3, RecordingBase.uint32z),
                RecordingFITField(4, RecordingBase.uint32),
            ])
        data(local: local, [4, 255, 1, 12_345, UInt64(created)])
    }

    /// The whole file: header, messages and CRC.
    func file(headerSize: Int = 14, headerCRC: Bool = true, extraDataSize: Int = 0) -> [UInt8] {
        var header: [UInt8] = [UInt8(headerSize), 0x20]
        header += RecordingBytes.encode(2132, size: 2)
        header += RecordingBytes.encode(UInt64(body.count + extraDataSize), size: 4)
        header += RecordingBytes.ascii(".FIT")
        if headerSize == 14 {
            let crc = headerCRC ? RecordingChecksum.crc16(header) : 0
            header += RecordingBytes.encode(UInt64(crc), size: 2)
        }
        let content = header + body
        return content + RecordingBytes.encode(UInt64(RecordingChecksum.crc16(content)), size: 2)
    }

    func data(headerSize: Int = 14) -> Data {
        Data(file(headerSize: headerSize))
    }

    private mutating func append(local: UInt8, values: [UInt64], developer: [UInt8]) {
        guard let definition = definitions[local] else {
            Issue.record("local message type \(local) is not defined")
            return
        }
        #expect(values.count == definition.fields.count)
        for (field, value) in zip(definition.fields, values) {
            body += RecordingBytes.encode(
                value, size: field.size, bigEndian: definition.bigEndian)
        }
        body += developer
    }
}

/// One data message of a parsed FIT file.
nonisolated struct RecordingFITMessage {
    let global: Int
    let bigEndian: Bool
    let fields: [Int: [UInt8]]
    /// The message's timestamp, from field 253 or a compressed timestamp header.
    let timestamp: UInt32?

    func unsigned(_ number: Int) -> UInt64? {
        fields[number].map { RecordingBytes.decode($0[...], bigEndian: bigEndian) }
    }

    func signed32(_ number: Int) -> Int32? {
        unsigned(number).map { Int32(bitPattern: UInt32(truncatingIfNeeded: $0)) }
    }
}

/// Why a FIT file could not be parsed by ``RecordingFITFile``.
nonisolated enum RecordingFITParseError: Error {
    case header
    case truncated
    case undefined(Int)
}

/// An independent FIT reader, written from the FIT protocol, to check what FITWriter writes.
nonisolated struct RecordingFITFile {
    private struct Definition {
        let global: Int
        let bigEndian: Bool
        let fields: [RecordingFITField]
        let developerSize: Int
    }

    let headerSize: Int
    let dataSize: Int
    let messages: [RecordingFITMessage]
    let definitionCount: Int

    init(_ bytes: [UInt8]) throws(RecordingFITParseError) {
        guard bytes.count >= 12, [12, 14].contains(Int(bytes[0])), bytes.count >= Int(bytes[0])
        else { throw .header }
        guard Array(bytes[8..<12]) == RecordingBytes.ascii(".FIT") else { throw .header }
        headerSize = Int(bytes[0])
        dataSize = Int(RecordingBytes.uint32(bytes, at: 4))
        let end = headerSize + dataSize
        guard bytes.count >= end else { throw .truncated }
        var definitions: [Int: Definition] = [:]
        var messages: [RecordingFITMessage] = []
        var definitionCount = 0
        var offset = headerSize
        var last: UInt32 = 0
        while offset < end {
            let header = bytes[offset]
            offset += 1
            if header & 0xC0 == 0x40 {
                definitions[Int(header & 0x0F)] = try Self.definition(
                    bytes, at: &offset, end: end, developer: header & 0x20 != 0)
                definitionCount += 1
                continue
            }
            let compressed = header & 0x80 != 0
            let local = Int(compressed ? (header >> 5) & 0x03 : header & 0x0F)
            guard let definition = definitions[local] else { throw .undefined(local) }
            var time: UInt32?
            if compressed {
                let timeOffset = UInt32(header & 0x1F)
                var resolved = (last & ~0x1F) + timeOffset
                if timeOffset < last & 0x1F {
                    resolved += 0x20
                }
                time = resolved
            }
            let message = try Self.message(
                bytes, at: &offset, end: end, definition: definition, time: time)
            if let timestamp = message.timestamp {
                last = timestamp
            }
            messages.append(message)
        }
        self.messages = messages
        self.definitionCount = definitionCount
    }

    func messages(_ global: Int) -> [RecordingFITMessage] {
        messages.filter { $0.global == global }
    }

    private static func definition(
        _ bytes: [UInt8], at offset: inout Int, end: Int, developer: Bool
    ) throws(RecordingFITParseError) -> Definition {
        guard offset + 5 <= end else { throw .truncated }
        let bigEndian = bytes[offset + 1] == 1
        let global = Int(
            RecordingBytes.decode(bytes[offset + 2..<offset + 4], bigEndian: bigEndian))
        let count = Int(bytes[offset + 4])
        offset += 5
        guard offset + 3 * count <= end else { throw .truncated }
        let fields = (0..<count).map { index in
            let start = offset + 3 * index
            return RecordingFITField(
                bytes[start], bytes[start + 2], size: Int(bytes[start + 1]))
        }
        offset += 3 * count
        var developerSize = 0
        if developer {
            guard offset < end else { throw .truncated }
            let developerCount = Int(bytes[offset])
            offset += 1
            guard offset + 3 * developerCount <= end else { throw .truncated }
            for index in 0..<developerCount {
                developerSize += Int(bytes[offset + 3 * index + 1])
            }
            offset += 3 * developerCount
        }
        return Definition(
            global: global, bigEndian: bigEndian, fields: fields, developerSize: developerSize)
    }

    private static func message(
        _ bytes: [UInt8], at offset: inout Int, end: Int, definition: Definition, time: UInt32?
    ) throws(RecordingFITParseError) -> RecordingFITMessage {
        var fields: [Int: [UInt8]] = [:]
        for field in definition.fields {
            guard offset + field.size <= end else { throw .truncated }
            fields[Int(field.number)] = Array(bytes[offset..<offset + field.size])
            offset += field.size
        }
        guard offset + definition.developerSize <= end else { throw .truncated }
        offset += definition.developerSize
        var timestamp = time
        if let raw = fields[253], raw.count == 4 {
            timestamp = UInt32(RecordingBytes.decode(raw[...], bigEndian: definition.bigEndian))
        }
        return RecordingFITMessage(
            global: definition.global, bigEndian: definition.bigEndian, fields: fields,
            timestamp: timestamp)
    }
}

/// Times, positions and activities for the tests.
nonisolated enum RecordingFixtures {
    /// FIT's epoch, 31 December 1989 00:00 UTC, as seconds since 1970.
    static let fitEpochUnix: TimeInterval = 631_065_600

    /// A start in 2025, on a whole second.
    static let start = Date(timeIntervalSince1970: 1_760_000_000)

    static func date(fit seconds: UInt32) -> Date {
        Date(timeIntervalSince1970: fitEpochUnix + Double(seconds))
    }

    static func fitSeconds(_ date: Date) -> UInt32 {
        UInt32(date.timeIntervalSince1970 - fitEpochUnix)
    }

    static func degrees(_ semicircles: Int32) -> Double {
        Double(semicircles) * 180 / 2_147_483_648
    }

    static func semicircles(_ degrees: Double) -> Int32 {
        Int32((degrees * 2_147_483_648 / 180).rounded())
    }

    /// Two's complement bits of a signed 32-bit value, as a field value.
    static func bits(_ value: Int32) -> UInt64 {
        UInt64(UInt32(bitPattern: value))
    }

    /// Records whose every value is representable in FIT exactly: whole seconds, positions
    /// in semicircles, altitude in fifths of a metre, centimetres and millimetres a second.
    static func randomRecords(
        _ count: Int, using random: inout RecordingRandom, fractionalCadence: Bool = false
    ) -> [FITActivity.Record] {
        var time = start
        var distance = 0
        return (0..<count).map { _ in
            time += Double(random.int(1...5))
            distance += random.int(0...2000)
            var record = FITActivity.Record(time: time)
            if random.chance(0.8) {
                record.latitude = degrees(Int32(random.int(-1_000_000_000...1_000_000_000)))
                record.longitude = degrees(Int32(random.int(-2_000_000_000...2_000_000_000)))
            }
            record.altitude = random.chance(0.8) ? Double(random.int(0...12_000)) / 5 - 500 : nil
            record.heartRate = random.chance(0.8) ? random.int(30...220) : nil
            let cadence = Double(random.int(0...200))
            let fraction = fractionalCadence ? Double(random.int(0...127)) / 128 : 0
            record.cadence = random.chance(0.8) ? cadence + fraction : nil
            record.distance = random.chance(0.8) ? Double(distance) / 100 : nil
            record.speed = random.chance(0.8) ? Double(random.int(0...20_000)) / 1000 : nil
            record.power = random.chance(0.8) ? random.int(0...2000) : nil
            return record
        }
    }

    static func randomLaps(_ count: Int, using random: inout RecordingRandom) -> [FITActivity.Lap] {
        (0..<count).map { index in
            FITActivity.Lap(
                start: random.chance(0.9) ? start + Double(600 * index) : nil,
                elapsed: random.chance(0.8) ? Double(random.int(1...4_000_000)) / 1000 : nil,
                moving: random.chance(0.8) ? Double(random.int(1...4_000_000)) / 1000 : nil,
                distance: random.chance(0.8) ? Double(random.int(0...5_000_000)) / 100 : nil,
                averageSpeed: random.chance(0.8) ? Double(random.int(0...20_000)) / 1000 : nil,
                averageHeartRate: random.chance(0.8) ? random.int(40...200) : nil,
                maxHeartRate: random.chance(0.8) ? random.int(40...220) : nil,
                ascent: random.chance(0.8) ? random.int(0...3000) : nil,
                averagePower: random.chance(0.8) ? random.int(0...1500) : nil)
        }
    }

    static func randomSets(
        _ count: Int, using random: inout RecordingRandom
    )
        -> [FITActivity.ExerciseSet]
    {
        (0..<count).map { index in
            FITActivity.ExerciseSet(
                start: random.chance(0.9) ? start + Double(120 * index) : nil,
                duration: random.chance(0.8) ? Double(random.int(1...300_000)) / 1000 : nil,
                repetitions: random.chance(0.8) ? random.int(0...50) : nil,
                weight: random.chance(0.8) ? Double(random.int(0...4000)) / 16 : nil,
                isActive: random.chance(0.6),
                category: random.chance(0.8) ? random.int(0...32) : nil)
        }
    }

    /// Alternating stops and starts, beginning with a start.
    static func randomTimerEvents(
        _ count: Int, using random: inout RecordingRandom
    )
        -> [FITActivity.TimerEvent]
    {
        var time = start
        return (0..<count).map { index in
            time += Double(random.int(1...900))
            return FITActivity.TimerEvent(time: time, isStart: index.isMultiple(of: 2))
        }
    }

    static func randomActivity(seed: UInt64, records: Int = 60) -> FITActivity {
        var random = RecordingRandom(seed: seed)
        return FITActivity(
            records: randomRecords(records, using: &random),
            laps: randomLaps(random.int(0...6), using: &random),
            sets: randomSets(random.int(0...6), using: &random),
            timerEvents: randomTimerEvents(random.int(0...6), using: &random))
    }

    /// Heart rate zones with floors 100, 120, 140, 160 and 175 bpm.
    static func zones() throws -> HeartRateZoneSet {
        try #require(
            HeartRateZoneSet(
                HeartRateZones(
                    zone1Floor: 100, zone2Floor: 120, zone3Floor: 140, zone4Floor: 160,
                    zone5Floor: 175, maxHeartRateUsed: 190, sport: "RUNNING")))
    }

    /// The zone, 0 to 4, of `heartRate` with the floors of ``zones()``.
    static func zone(of heartRate: Int) -> Int {
        [120, 140, 160, 175].count { heartRate >= $0 }
    }

    static func close(
        _ actual: Double?, _ expected: Double?, within tolerance: Double = 1e-9
    )
        -> Bool
    {
        switch (actual, expected) {
        case (nil, nil): true
        case (let actual?, let expected?): abs(actual - expected) <= tolerance
        default: false
        }
    }
}
