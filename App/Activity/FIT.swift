import Foundation

/// The parts of a FIT activity file, the binary format Garmin devices record in, that the
/// activity screens use: the recorded samples, the laps and strength training sets.
nonisolated struct FITActivity: Hashable, Sendable {
    /// One recorded sample.
    struct Record: Hashable, Sendable {
        var time: Date
        var latitude: Double?
        var longitude: Double?
        /// Metres above sea level.
        var altitude: Double?
        var heartRate: Int?
        /// Revolutions or strides per minute, including Garmin's fractional part.
        var cadence: Double?
        /// Metres from the start.
        var distance: Double?
        /// Metres per second.
        var speed: Double?
        /// Watts.
        var power: Int?
    }

    struct Lap: Hashable, Sendable {
        var start: Date?
        /// Seconds from start to end, and seconds of the timer running.
        var elapsed: Double?
        var moving: Double?
        /// Metres.
        var distance: Double?
        /// Metres per second.
        var averageSpeed: Double?
        var averageHeartRate: Int?
        var maxHeartRate: Int?
        /// Metres climbed.
        var ascent: Int?
        var averagePower: Int?
    }

    /// A strength training set.
    struct ExerciseSet: Hashable, Sendable {
        var start: Date?
        /// Seconds.
        var duration: Double?
        var repetitions: Int?
        /// Kilograms.
        var weight: Double?
        /// Active sets, as opposed to rests.
        var isActive: Bool
        /// The FIT profile's exercise category, such as 0 for bench press.
        var category: Int?
    }

    /// When the timer started or stopped: pauses lie between a stop and the next start.
    struct TimerEvent: Hashable, Sendable {
        var time: Date
        var isStart: Bool
    }

    var records: [Record] = []
    var laps: [Lap] = []
    var sets: [ExerciseSet] = []
    var timerEvents: [TimerEvent] = []

    /// FIT timestamps count seconds from 31 December 1989, 00:00 UTC.
    static let epoch = Date(timeIntervalSince1970: 631_065_600)

    /// The activity in `data`, a FIT file.
    init(decoding data: Data) throws(FITError) {
        var decoder = FITDecoder(bytes: [UInt8](data))
        self = try decoder.decode()
    }

    init(
        records: [Record] = [], laps: [Lap] = [], sets: [ExerciseSet] = [],
        timerEvents: [TimerEvent] = []
    ) {
        self.records = records
        self.laps = laps
        self.sets = sets
        self.timerEvents = timerEvents
    }
}

/// Why a file could not be read as FIT.
nonisolated enum FITError: Error, Equatable {
    case notFIT
    case truncated
    case undefinedMessage(local: Int)
}

/// FIT base types: their byte sizes and invalid values, by base type number.
nonisolated enum FITBaseType {
    static func size(_ type: UInt8) -> Int {
        switch type & 0x1F {
        case 0x00, 0x01, 0x02, 0x07, 0x0A, 0x0D: 1
        case 0x03, 0x04, 0x0B: 2
        case 0x05, 0x06, 0x08, 0x0C: 4
        case 0x09, 0x0E, 0x0F, 0x10: 8
        default: 0
        }
    }

    /// The number in `raw`, or `nil` for the type's invalid value and for strings.
    static func value(_ raw: UInt64, type: UInt8) -> Double? {
        switch type & 0x1F {
        case 0x00, 0x02, 0x0D: raw == 0xFF ? nil : Double(raw)
        case 0x01: raw == 0x7F ? nil : Double(Int8(truncatingIfNeeded: raw))
        case 0x03: raw == 0x7FFF ? nil : Double(Int16(truncatingIfNeeded: raw))
        case 0x04: raw == 0xFFFF ? nil : Double(raw)
        case 0x05: raw == 0x7FFF_FFFF ? nil : Double(Int32(truncatingIfNeeded: raw))
        case 0x06: raw == 0xFFFF_FFFF ? nil : Double(raw)
        case 0x08:
            raw == 0xFFFF_FFFF ? nil : Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw)))
        case 0x09: raw == UInt64.max ? nil : Double(bitPattern: raw)
        case 0x0A, 0x0B, 0x0C, 0x10: raw == 0 ? nil : Double(raw)
        case 0x0E: raw == 0x7FFF_FFFF_FFFF_FFFF ? nil : Double(Int64(bitPattern: raw))
        case 0x0F: raw == UInt64.max ? nil : Double(raw)
        default: nil
        }
    }
}

/// Reads a FIT file's messages, keeping records (20), laps (19), timer events (21) and sets
/// (225).
nonisolated private struct FITDecoder {
    struct Field {
        let number: UInt8
        let size: Int
        let type: UInt8
    }

    struct Definition {
        let global: UInt16
        let bigEndian: Bool
        let fields: [Field]
        let developerBytes: Int
    }

    let bytes: [UInt8]
    var offset = 0
    var definitions: [Int: Definition] = [:]
    var lastTimestamp: UInt32 = 0

    mutating func decode() throws(FITError) -> FITActivity {
        guard bytes.count >= 12, Array(bytes[8..<12]) == Array(".FIT".utf8) else {
            throw .notFIT
        }
        let headerSize = Int(bytes[0])
        let dataSize = Int(integer(at: 4, size: 4, bigEndian: false))
        let end = headerSize + dataSize
        guard headerSize >= 12, end <= bytes.count else { throw .truncated }
        offset = headerSize
        var activity = FITActivity()
        while offset < end {
            let header = try byte()
            if header & 0x80 != 0 {
                // A compressed timestamp header: five bits of seconds after the last timestamp.
                let seconds = UInt32(header & 0x1F)
                var timestamp = (lastTimestamp & ~0x1F) + seconds
                if seconds < lastTimestamp & 0x1F {
                    timestamp += 0x20
                }
                lastTimestamp = timestamp
                try readData(local: Int((header >> 5) & 0x03), into: &activity)
            } else if header & 0x40 != 0 {
                try readDefinition(local: Int(header & 0x0F), developer: header & 0x20 != 0)
            } else {
                try readData(local: Int(header & 0x0F), into: &activity)
            }
        }
        return activity
    }

    private mutating func byte() throws(FITError) -> UInt8 {
        guard offset < bytes.count else { throw .truncated }
        defer { offset += 1 }
        return bytes[offset]
    }

    private mutating func skip(_ count: Int) throws(FITError) {
        guard offset + count <= bytes.count else { throw .truncated }
        offset += count
    }

    private func integer(at start: Int, size: Int, bigEndian: Bool) -> UInt64 {
        (0..<size).reduce(0) { value, index in
            let byte = UInt64(bytes[start + (bigEndian ? index : size - 1 - index)])
            return value << 8 | byte
        }
    }

    private mutating func readDefinition(local: Int, developer: Bool) throws(FITError) {
        try skip(1)
        let bigEndian = try byte() == 1
        guard offset + 3 <= bytes.count else { throw .truncated }
        let global = UInt16(integer(at: offset, size: 2, bigEndian: bigEndian))
        offset += 2
        let count = Int(try byte())
        var fields: [Field] = []
        for _ in 0..<count {
            fields.append(Field(number: try byte(), size: Int(try byte()), type: try byte()))
        }
        var developerBytes = 0
        if developer {
            for _ in 0..<Int(try byte()) {
                try skip(1)
                developerBytes += Int(try byte())
                try skip(1)
            }
        }
        definitions[local] = Definition(
            global: global, bigEndian: bigEndian, fields: fields, developerBytes: developerBytes)
    }

    private mutating func readData(local: Int, into activity: inout FITActivity) throws(FITError) {
        guard let definition = definitions[local] else { throw .undefinedMessage(local: local) }
        var values: [UInt8: Double] = [:]
        for field in definition.fields {
            guard offset + field.size <= bytes.count else { throw .truncated }
            let size = FITBaseType.size(field.type)
            // Arrays keep their first element; strings are skipped.
            if size > 0, field.size >= size, field.type & 0x1F != 0x07 {
                let raw = integer(at: offset, size: size, bigEndian: definition.bigEndian)
                values[field.number] = FITBaseType.value(raw, type: field.type)
            }
            offset += field.size
        }
        try skip(definition.developerBytes)
        if let timestamp = values[253] {
            lastTimestamp = UInt32(timestamp)
        }
        switch definition.global {
        case 20: activity.records.append(record(values))
        case 19: activity.laps.append(lap(values))
        case 225: activity.sets.append(exerciseSet(values))
        case 21:
            // Timer events: start (0), and stop (1), stop all (4) and their disabling kinds.
            if values[0] == 0, let type = values[1], let time = date(values[253]) {
                if type == 0 {
                    activity.timerEvents.append(.init(time: time, isStart: true))
                } else if [1, 4, 8, 9].contains(type) {
                    activity.timerEvents.append(.init(time: time, isStart: false))
                }
            }
        default: break
        }
    }

    private func date(_ seconds: Double?) -> Date? {
        seconds.map { FITActivity.epoch.addingTimeInterval($0) }
    }

    private func record(_ values: [UInt8: Double]) -> FITActivity.Record {
        let degrees = 180 / 2_147_483_648.0
        return FITActivity.Record(
            time: date(values[253]) ?? FITActivity.epoch.addingTimeInterval(Double(lastTimestamp)),
            latitude: values[0].map { $0 * degrees },
            longitude: values[1].map { $0 * degrees },
            altitude: (values[78] ?? values[2]).map { $0 / 5 - 500 },
            heartRate: values[3].map { Int($0) },
            cadence: values[4].map { $0 + (values[53] ?? 0) / 128 },
            distance: values[5].map { $0 / 100 },
            speed: (values[73] ?? values[6]).map { $0 / 1000 },
            power: values[7].map { Int($0) })
    }

    private func lap(_ values: [UInt8: Double]) -> FITActivity.Lap {
        FITActivity.Lap(
            start: date(values[2]),
            elapsed: values[7].map { $0 / 1000 },
            moving: values[8].map { $0 / 1000 },
            distance: values[9].map { $0 / 100 },
            averageSpeed: (values[110] ?? values[13]).map { $0 / 1000 },
            averageHeartRate: values[15].map { Int($0) },
            maxHeartRate: values[16].map { Int($0) },
            ascent: values[21].map { Int($0) },
            averagePower: values[19].map { Int($0) })
    }

    private func exerciseSet(_ values: [UInt8: Double]) -> FITActivity.ExerciseSet {
        FITActivity.ExerciseSet(
            start: date(values[6]),
            duration: values[0].map { $0 / 1000 },
            repetitions: values[3].map { Int($0) },
            weight: values[4].map { $0 / 16 },
            isActive: values[5] == 1,
            category: values[7].map { Int($0) })
    }
}
