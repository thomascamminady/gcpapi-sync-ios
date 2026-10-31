import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// Hand-built FIT files, byte by byte from the FIT protocol, decoded by `FITActivity`.
@Suite("FIT decoding of hand-built files")
struct BlackBoxFITDecodingTests {
    typealias Field = RecordingFITField
    typealias Base = RecordingBase

    static let time: UInt32 = 1_000_000_000

    /// The record message's timestamp, position, altitude, heart rate, cadence, distance,
    /// speed and power, with their profile base types.
    static let recordFields = [
        Field(253, Base.uint32), Field(0, Base.sint32), Field(1, Base.sint32),
        Field(2, Base.uint16), Field(3, Base.uint8), Field(4, Base.uint8),
        Field(5, Base.uint32), Field(6, Base.uint16), Field(7, Base.uint16),
    ]

    static let latitude = RecordingFixtures.semicircles(40.7128)
    static let longitude = RecordingFixtures.semicircles(-74.006)

    /// 12.4 m, 151 bpm, 87 rpm, 1234.56 m, 3.456 m/s and 287 W.
    static let recordValues: [UInt64] = [
        UInt64(time), RecordingFixtures.bits(latitude), RecordingFixtures.bits(longitude),
        2562, 151, 87, 123_456, 3456, 287,
    ]

    /// The invalid value of each record field, by index into ``recordFields``.
    static let invalidValues: [UInt64] = [
        0xFFFF_FFFF, 0x7FFF_FFFF, 0x7FFF_FFFF, 0xFFFF, 0xFF, 0xFF, 0xFFFF_FFFF, 0xFFFF, 0xFFFF,
    ]

    static func decode(
        _ builder: RecordingFITBuilder, headerSize: Int = 14
    ) throws
        -> FITActivity
    {
        try FITActivity(decoding: builder.data(headerSize: headerSize))
    }

    static func recordFile(bigEndian: Bool, values: [UInt64]) -> RecordingFITBuilder {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(local: 1, global: 20, bigEndian: bigEndian, fields: recordFields)
        builder.data(local: 1, values)
        return builder
    }

    @Test("Every record field decodes in either byte order", arguments: [false, true])
    func decodesEveryRecordField(bigEndian: Bool) throws {
        let fit = try Self.decode(Self.recordFile(bigEndian: bigEndian, values: Self.recordValues))
        #expect(fit.records.count == 1)
        let record = try #require(fit.records.first)
        #expect(record.time == RecordingFixtures.date(fit: Self.time))
        #expect(
            RecordingFixtures.close(
                record.latitude, RecordingFixtures.degrees(Self.latitude), within: 1e-9))
        #expect(
            RecordingFixtures.close(
                record.longitude, RecordingFixtures.degrees(Self.longitude), within: 1e-9))
        #expect(RecordingFixtures.close(record.latitude, 40.7128, within: 1e-6))
        #expect(RecordingFixtures.close(record.longitude, -74.006, within: 1e-6))
        #expect(RecordingFixtures.close(record.altitude, 12.4, within: 1e-9))
        #expect(record.heartRate == 151)
        #expect(RecordingFixtures.close(record.cadence, 87))
        #expect(RecordingFixtures.close(record.distance, 1234.56, within: 1e-9))
        #expect(RecordingFixtures.close(record.speed, 3.456, within: 1e-9))
        #expect(record.power == 287)
        #expect(fit.laps.isEmpty)
        #expect(fit.sets.isEmpty)
        #expect(fit.timerEvents.isEmpty)
    }

    @Test("A field's invalid value decodes as nil", arguments: 1...8, [false, true])
    func invalidFieldIsNil(index: Int, bigEndian: Bool) throws {
        var values = Self.recordValues
        values[index] = Self.invalidValues[index]
        let fit = try Self.decode(Self.recordFile(bigEndian: bigEndian, values: values))
        let record = try #require(fit.records.first)
        let present = [
            record.latitude != nil, record.longitude != nil, record.altitude != nil,
            record.heartRate != nil, record.cadence != nil, record.distance != nil,
            record.speed != nil, record.power != nil,
        ]
        for (property, isPresent) in present.enumerated() {
            if property == index - 1 {
                #expect(!isPresent, "property \(property) should be nil")
            } else if index <= 2, property <= 1 {
                // Without one coordinate the other may be dropped as well.
                continue
            } else {
                #expect(isPresent, "property \(property) should be decoded")
            }
        }
        #expect(record.time == RecordingFixtures.date(fit: Self.time))
    }

    @Test("A record of invalid values has only its time", arguments: [false, true])
    func allInvalidValues(bigEndian: Bool) throws {
        var values = Self.invalidValues
        values[0] = UInt64(Self.time)
        let fit = try Self.decode(Self.recordFile(bigEndian: bigEndian, values: values))
        let record = try #require(fit.records.first)
        #expect(record == FITActivity.Record(time: RecordingFixtures.date(fit: Self.time)))
    }

    @Test("Southern and eastern coordinates are negative and positive", arguments: [false, true])
    func signedCoordinates(bigEndian: Bool) throws {
        var values = Self.recordValues
        let south = RecordingFixtures.semicircles(-33.8688)
        let east = RecordingFixtures.semicircles(151.2093)
        values[1] = RecordingFixtures.bits(south)
        values[2] = RecordingFixtures.bits(east)
        let fit = try Self.decode(Self.recordFile(bigEndian: bigEndian, values: values))
        let record = try #require(fit.records.first)
        #expect(RecordingFixtures.close(record.latitude, -33.8688, within: 1e-6))
        #expect(RecordingFixtures.close(record.longitude, 151.2093, within: 1e-6))
    }

    @Test(
        "Altitude has an offset of 500 m",
        arguments: [(0, -500.0), (2400, -20), (65_534, 12_606.8)])
    func altitudeOffset(raw: UInt64, metres: Double) throws {
        var values = Self.recordValues
        values[3] = raw
        let fit = try Self.decode(Self.recordFile(bigEndian: false, values: values))
        #expect(RecordingFixtures.close(fit.records.first?.altitude, metres, within: 1e-9))
    }

    @Test("Enhanced speed and altitude are read", arguments: [false, true])
    func enhancedSpeedAndAltitude(bigEndian: Bool) throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(
            local: 2, global: 20, bigEndian: bigEndian,
            fields: [Field(253, Base.uint32), Field(73, Base.uint32), Field(78, Base.uint32)])
        builder.data(local: 2, [UInt64(Self.time), 4250, 10_000])
        let record = try #require(try Self.decode(builder).records.first)
        #expect(RecordingFixtures.close(record.speed, 4.25, within: 1e-9))
        #expect(RecordingFixtures.close(record.altitude, 1500, within: 1e-9))
    }

    @Test("Legacy and enhanced fields together agree")
    func legacyAndEnhancedTogether() throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(
            local: 2, global: 20,
            fields: [
                Field(253, Base.uint32), Field(6, Base.uint16), Field(73, Base.uint32),
                Field(2, Base.uint16), Field(78, Base.uint32),
            ])
        builder.data(local: 2, [UInt64(Self.time), 3100, 3100, 3000, 3000])
        let record = try #require(try Self.decode(builder).records.first)
        #expect(RecordingFixtures.close(record.speed, 3.1, within: 1e-9))
        #expect(RecordingFixtures.close(record.altitude, 100, within: 1e-9))
    }

    @Test("Cadence includes Garmin's fractional part")
    func fractionalCadence() throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(
            local: 2, global: 20,
            fields: [Field(253, Base.uint32), Field(4, Base.uint8), Field(53, Base.uint8)])
        builder.data(local: 2, [UInt64(Self.time), 85, 64])
        builder.data(local: 2, [UInt64(Self.time + 1), 90, 32])
        builder.data(local: 2, [UInt64(Self.time + 2), 80, 0xFF])
        let cadences = try Self.decode(builder).records.map(\.cadence)
        #expect(cadences == [85.5, 90.25, 80])
    }

    @Test("Header variants: 12 bytes, or 14 with or without a header CRC")
    func headerVariants() throws {
        let builder = Self.recordFile(bigEndian: false, values: Self.recordValues)
        for file in [
            builder.file(headerSize: 12), builder.file(headerSize: 14, headerCRC: false),
            builder.file(headerSize: 14, headerCRC: true),
        ] {
            let fit = try FITActivity(decoding: Data(file))
            #expect(fit.records.count == 1)
            #expect(fit.records.first?.heartRate == 151)
        }
    }

    @Test("Records keep their file order")
    func recordOrder() throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(
            local: 3, global: 20, fields: [Field(253, Base.uint32), Field(3, Base.uint8)])
        for index in 0..<100 {
            builder.data(local: 3, [UInt64(Self.time) + UInt64(index), UInt64(60 + index)])
        }
        let records = try Self.decode(builder).records
        #expect(records.map(\.heartRate) == (60..<160).map(\.self))
        #expect(
            records.map(\.time) == (0..<100).map { RecordingFixtures.date(fit: Self.time + $0) })
    }

    @Test("All sixteen local message types can be used at once")
    func sixteenLocalTypes() throws {
        var builder = RecordingFITBuilder()
        for local in UInt8(0)...15 {
            builder.define(
                local: local, global: 20,
                fields: [Field(253, Base.uint32), Field(3, Base.uint8)])
        }
        let order: [UInt8] = [15, 0, 7, 3, 12, 1, 9, 14, 2, 11, 5, 8, 4, 13, 6, 10]
        for (index, local) in order.enumerated() {
            builder.data(local: local, [UInt64(Self.time) + UInt64(index), 100 + UInt64(local)])
        }
        let records = try Self.decode(builder).records
        #expect(records.map(\.heartRate) == order.map { 100 + Int($0) })
    }

    @Test("A local message type can be redefined", arguments: [false, true])
    func redefinition(bigEndian: Bool) throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(
            local: 0, global: 20, bigEndian: bigEndian,
            fields: [Field(253, Base.uint32), Field(3, Base.uint8)])
        builder.data(local: 0, [UInt64(Self.time), 120])
        builder.define(
            local: 0, global: 21, bigEndian: !bigEndian,
            fields: [
                Field(253, Base.uint32), Field(0, Base.enumeration),
                Field(1, Base.enumeration),
            ])
        builder.data(local: 0, [UInt64(Self.time + 5), 0, 1])
        builder.define(
            local: 0, global: 20, bigEndian: bigEndian,
            fields: [Field(7, Base.uint16), Field(3, Base.uint8), Field(253, Base.uint32)])
        builder.data(local: 0, [300, 130, UInt64(Self.time + 10)])
        let fit = try Self.decode(builder)
        #expect(fit.records.map(\.heartRate) == [120, 130])
        #expect(fit.records.map(\.power) == [nil, 300])
        #expect(fit.records.last?.time == RecordingFixtures.date(fit: Self.time + 10))
        #expect(
            fit.timerEvents == [
                FITActivity.TimerEvent(
                    time: RecordingFixtures.date(fit: Self.time + 5), isStart: false)
            ])
    }

    @Test("Messages the activity does not use are skipped", arguments: [false, true])
    func unknownMessagesAreSkipped(bigEndian: Bool) throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        // device_info with a product name, session, activity and a manufacturer message.
        builder.define(
            local: 1, global: 23, bigEndian: bigEndian,
            fields: [
                Field(253, Base.uint32), Field(0, Base.uint8), Field(2, Base.uint16),
                Field(27, Base.string, size: 20),
            ])
        builder.data(
            local: 1,
            fields: [
                RecordingBytes.encode(UInt64(Self.time), size: 4, bigEndian: bigEndian), [0],
                RecordingBytes.encode(1, size: 2, bigEndian: bigEndian),
                RecordingBytes.string("Forerunner 965", size: 20),
            ])
        builder.define(
            local: 2, global: 18, bigEndian: bigEndian,
            fields: [Field(253, Base.uint32), Field(7, Base.uint32), Field(9, Base.uint32)])
        builder.data(local: 2, [UInt64(Self.time), 3_600_000, 1_000_000])
        builder.define(
            local: 3, global: 0xFF00, bigEndian: bigEndian,
            fields: [Field(0, Base.byte, size: 7), Field(1, Base.sint16)])
        builder.data(local: 3, fields: [[0x40, 0x41, 0x80, 0xFF, 0x00, 0x14, 0x15], [1, 2]])
        builder.define(
            local: 4, global: 20, bigEndian: bigEndian,
            fields: [Field(253, Base.uint32), Field(3, Base.uint8)])
        builder.data(local: 4, [UInt64(Self.time + 1), 99])
        builder.define(
            local: 5, global: 34, bigEndian: bigEndian,
            fields: [Field(253, Base.uint32), Field(1, Base.uint16), Field(2, Base.enumeration)])
        builder.data(local: 5, [UInt64(Self.time + 2), 1, 0])
        let fit = try Self.decode(builder)
        #expect(fit.records.map(\.heartRate) == [99])
        #expect(fit.laps.isEmpty)
        #expect(fit.sets.isEmpty)
        #expect(fit.timerEvents.isEmpty)
    }

    @Test("String fields are skipped by their size")
    func stringFields() throws {
        var builder = RecordingFITBuilder()
        builder.define(
            local: 0, global: 0,
            fields: [Field(0, Base.enumeration), Field(8, Base.string, size: 20)])
        builder.data(local: 0, fields: [[4], RecordingBytes.string("Läuft 🏃", size: 20)])
        builder.define(
            local: 1, global: 20,
            fields: [
                Field(253, Base.uint32), Field(200, Base.string, size: 12), Field(3, Base.uint8),
                Field(201, Base.string, size: 1), Field(7, Base.uint16),
            ])
        builder.data(
            local: 1,
            fields: [
                RecordingBytes.encode(UInt64(Self.time), size: 4),
                RecordingBytes.string("hello world", size: 12), [142], [0],
                RecordingBytes.encode(222, size: 2),
            ])
        let records = try Self.decode(builder).records
        #expect(records.count == 1)
        #expect(records.first?.heartRate == 142)
        #expect(records.first?.power == 222)
        #expect(records.first?.time == RecordingFixtures.date(fit: Self.time))
    }

    @Test("Array fields are skipped by their size", arguments: [false, true])
    func arrayFields(bigEndian: Bool) throws {
        var builder = RecordingFITBuilder()
        builder.define(
            local: 0, global: 20, bigEndian: bigEndian,
            fields: [
                Field(253, Base.uint32), Field(150, Base.uint16, size: 8), Field(3, Base.uint8),
                Field(151, Base.uint8, size: 3), Field(152, Base.sint32, size: 12),
                Field(7, Base.uint16),
            ])
        builder.data(
            local: 0,
            fields: [
                RecordingBytes.encode(UInt64(Self.time), size: 4, bigEndian: bigEndian),
                [1, 2, 3, 4, 5, 6, 7, 8], [133], [9, 9, 9], [UInt8](repeating: 0x55, count: 12),
                RecordingBytes.encode(345, size: 2, bigEndian: bigEndian),
            ])
        let record = try #require(try Self.decode(builder).records.first)
        #expect(record.heartRate == 133)
        #expect(record.power == 345)
    }

    @Test("Developer fields are skipped", arguments: [false, true])
    func developerFields(bigEndian: Bool) throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(
            local: 1, global: 207, bigEndian: bigEndian,
            fields: [Field(1, Base.byte, size: 16), Field(3, Base.uint8)])
        builder.data(local: 1, fields: [[UInt8](repeating: 0xAB, count: 16), [0]])
        builder.define(
            local: 2, global: 206, bigEndian: bigEndian,
            fields: [
                Field(0, Base.uint8), Field(1, Base.uint8), Field(2, Base.uint8),
                Field(3, Base.string, size: 16), Field(8, Base.string, size: 8),
            ])
        builder.data(
            local: 2,
            fields: [
                [0], [0], [0x84], RecordingBytes.string("Stride", size: 16),
                RecordingBytes.string("mm", size: 8),
            ])
        builder.data(
            local: 2,
            fields: [
                [0], [1], [0x0D], RecordingBytes.string("Blob", size: 16),
                RecordingBytes.string("", size: 8),
            ])
        builder.define(
            local: 3, global: 20, bigEndian: bigEndian,
            fields: [Field(253, Base.uint32), Field(3, Base.uint8)],
            developer: [Field(0, 0, size: 2), Field(1, 0, size: 5)])
        builder.data(
            local: 3, [UInt64(Self.time), 140],
            developer: [0x41, 0x42, 0x40, 0x03, 0x80, 0xC5, 0x46])
        builder.data(
            local: 3, [UInt64(Self.time + 1), 141],
            developer: [0x00, 0x01, 0x4F, 0x4F, 0x4F, 0x4F, 0x4F])
        builder.define(
            local: 4, global: 20, bigEndian: bigEndian,
            fields: [Field(253, Base.uint32), Field(3, Base.uint8)])
        builder.data(local: 4, [UInt64(Self.time + 2), 142])
        let records = try Self.decode(builder).records
        #expect(records.map(\.heartRate) == [140, 141, 142])
        #expect(records.map(\.time) == (0..<3).map { RecordingFixtures.date(fit: Self.time + $0) })
    }
}

/// Compressed timestamp headers: a five-bit offset from the last timestamp.
@Suite("FIT compressed timestamps")
struct BlackBoxFITCompressedTimestampTests {
    typealias Field = RecordingFITField
    typealias Base = RecordingBase

    /// A timestamp whose low five bits are 28.
    static let base: UInt32 = 1_000_000_028

    @Test("The five-bit offset rolls over", arguments: [false, true])
    func rollOver(bigEndian: Bool) throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(
            local: 0, global: 20, bigEndian: bigEndian,
            fields: [Field(253, Base.uint32), Field(3, Base.uint8)])
        builder.define(local: 1, global: 20, bigEndian: bigEndian, fields: [Field(3, Base.uint8)])
        builder.data(local: 0, [UInt64(Self.base), 100])
        let offsets: [UInt8] = [30, 31, 1, 1, 5, 4, 0, 31]
        for (index, offset) in offsets.enumerated() {
            builder.compressed(local: 1, offset: offset, [UInt64(101 + index)])
        }
        let records = try FITActivity(decoding: builder.data()).records
        let expected: [UInt32] = [0, 2, 3, 5, 5, 9, 40, 68, 99]
        #expect(records.map(\.heartRate) == (100...108).map(\.self))
        #expect(records.map(\.time) == expected.map { RecordingFixtures.date(fit: Self.base + $0) })
    }

    @Test("Random gaps of up to 31 seconds are recovered", arguments: 0..<12)
    func randomGaps(seed: Int) throws {
        var random = RecordingRandom(seed: UInt64(seed) + 1000)
        var builder = RecordingFITBuilder()
        builder.fileID()
        let local = UInt8(seed % 4)
        builder.define(
            local: 3 - local, global: 20, bigEndian: seed.isMultiple(of: 2),
            fields: [Field(253, Base.uint32), Field(3, Base.uint8)])
        builder.define(
            local: local, global: 20, bigEndian: !seed.isMultiple(of: 2),
            fields: [Field(3, Base.uint8), Field(7, Base.uint16)])
        var time = UInt32(random.int(900_000_000...1_100_000_000))
        builder.data(local: 3 - local, [UInt64(time), 60])
        var expected = [time]
        for index in 0..<300 {
            time += UInt32(random.int(0...31))
            expected.append(time)
            builder.compressed(local: local, offset: UInt8(time & 0x1F), [61, UInt64(index)])
        }
        let records = try FITActivity(decoding: builder.data()).records
        #expect(records.count == expected.count)
        #expect(records.map(\.time) == expected.map(RecordingFixtures.date(fit:)))
        #expect(records.dropFirst().map(\.power) == (0..<300).map(\.self))
    }

    @Test("The last timestamp of any message is the reference")
    func referenceFromAnEvent() throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(
            local: 0, global: 21,
            fields: [
                Field(253, Base.uint32), Field(0, Base.enumeration), Field(1, Base.enumeration),
            ])
        builder.define(local: 1, global: 20, fields: [Field(3, Base.uint8)])
        builder.data(local: 0, [UInt64(Self.base), 0, 0])
        builder.compressed(local: 1, offset: 31, [120])
        builder.compressed(local: 1, offset: 2, [121])
        let fit = try FITActivity(decoding: builder.data())
        #expect(
            fit.timerEvents == [
                FITActivity.TimerEvent(time: RecordingFixtures.date(fit: Self.base), isStart: true)
            ])
        #expect(
            fit.records.map(\.time) == [3, 6].map { RecordingFixtures.date(fit: Self.base + $0) })
    }
}

/// Laps, strength sets and timer events from hand-built messages.
@Suite("FIT laps, sets and timer events")
struct BlackBoxFITMessagesTests {
    typealias Field = RecordingFITField
    typealias Base = RecordingBase

    static let time: UInt32 = 1_000_000_000

    static let lapFields = [
        Field(253, Base.uint32), Field(2, Base.uint32), Field(7, Base.uint32),
        Field(8, Base.uint32), Field(9, Base.uint32), Field(13, Base.uint16),
        Field(15, Base.uint8), Field(16, Base.uint8), Field(21, Base.uint16),
        Field(19, Base.uint16),
    ]

    static let setFields = [
        Field(254, Base.uint32), Field(0, Base.uint32), Field(3, Base.uint16),
        Field(4, Base.uint16), Field(5, Base.uint8), Field(6, Base.uint32),
        Field(7, Base.uint16, size: 4), Field(8, Base.uint16, size: 4),
    ]

    static let eventFields = [
        Field(253, Base.uint32), Field(0, Base.enumeration), Field(1, Base.enumeration),
        Field(3, Base.uint32), Field(4, Base.uint8),
    ]

    @Test("Lap fields decode with their scales", arguments: [false, true])
    func lap(bigEndian: Bool) throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(local: 1, global: 19, bigEndian: bigEndian, fields: Self.lapFields)
        builder.data(
            local: 1,
            [
                UInt64(Self.time + 601), UInt64(Self.time), 600_500, 580_250, 200_050, 3448, 150,
                172, 42, 250,
            ])
        let fit = try FITActivity(decoding: builder.data())
        #expect(fit.laps.count == 1)
        let lap = try #require(fit.laps.first)
        #expect(lap.start == RecordingFixtures.date(fit: Self.time))
        #expect(RecordingFixtures.close(lap.elapsed, 600.5, within: 1e-9))
        #expect(RecordingFixtures.close(lap.moving, 580.25, within: 1e-9))
        #expect(RecordingFixtures.close(lap.distance, 2000.5, within: 1e-9))
        #expect(RecordingFixtures.close(lap.averageSpeed, 3.448, within: 1e-9))
        #expect(lap.averageHeartRate == 150)
        #expect(lap.maxHeartRate == 172)
        #expect(lap.ascent == 42)
        #expect(lap.averagePower == 250)
        #expect(fit.records.isEmpty)
    }

    @Test("A lap of invalid values has none")
    func invalidLap() throws {
        var builder = RecordingFITBuilder()
        builder.define(local: 1, global: 19, fields: Self.lapFields)
        builder.data(
            local: 1,
            [
                UInt64(Self.time), 0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF, 0xFF,
                0xFF, 0xFFFF, 0xFFFF,
            ])
        let fit = try FITActivity(decoding: builder.data())
        #expect(fit.laps == [FITActivity.Lap()])
    }

    @Test("Enhanced average speed is read")
    func enhancedLapSpeed() throws {
        var builder = RecordingFITBuilder()
        builder.define(
            local: 1, global: 19,
            fields: [Field(253, Base.uint32), Field(2, Base.uint32), Field(110, Base.uint32)])
        builder.data(local: 1, [UInt64(Self.time + 10), UInt64(Self.time), 3448])
        let lap = try #require(try FITActivity(decoding: builder.data()).laps.first)
        #expect(RecordingFixtures.close(lap.averageSpeed, 3.448, within: 1e-9))
    }

    @Test("Strength sets: active sets and rests", arguments: [false, true])
    func sets(bigEndian: Bool) throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(local: 2, global: 225, bigEndian: bigEndian, fields: Self.setFields)
        let category = RecordingBytes.encode(28, size: 2, bigEndian: bigEndian) + [0xFF, 0xFF]
        let none = [UInt8](repeating: 0xFF, count: 4)
        let words = { (value: UInt64, size: Int) in
            RecordingBytes.encode(value, size: size, bigEndian: bigEndian)
        }
        builder.data(
            local: 2,
            fields: [
                words(UInt64(Self.time + 46), 4), words(45_500, 4), words(8, 2), words(1320, 2),
                [1], words(UInt64(Self.time), 4), category, none,
            ])
        builder.data(
            local: 2,
            fields: [
                words(UInt64(Self.time + 136), 4), words(90_000, 4), words(0xFFFF, 2),
                words(0xFFFF, 2), [0], words(UInt64(Self.time + 46), 4), none, none,
            ])
        let sets = try FITActivity(decoding: builder.data()).sets
        #expect(sets.count == 2)
        let active = try #require(sets.first)
        #expect(active.start == RecordingFixtures.date(fit: Self.time))
        #expect(RecordingFixtures.close(active.duration, 45.5, within: 1e-9))
        #expect(active.repetitions == 8)
        #expect(RecordingFixtures.close(active.weight, 82.5, within: 1e-9))
        #expect(active.isActive)
        #expect(active.category == 28)
        let rest = try #require(sets.last)
        #expect(rest.start == RecordingFixtures.date(fit: Self.time + 46))
        #expect(RecordingFixtures.close(rest.duration, 90, within: 1e-9))
        #expect(rest.repetitions == nil)
        #expect(rest.weight == nil)
        #expect(!rest.isActive)
        #expect(rest.category == nil)
    }

    @Test("Timer starts and stops are timer events; other events are not")
    func timerEvents() throws {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(local: 3, global: 21, fields: Self.eventFields)
        let events: [(seconds: UInt32, event: UInt64, type: UInt64)] = [
            (0, 0, 0), (10, 9, 3), (100, 0, 1), (160, 0, 0), (170, 42, 3), (300, 0, 1),
            (310, 3, 0), (400, 0, 0), (500, 0, 1),
        ]
        for event in events {
            builder.data(
                local: 3, [UInt64(Self.time + event.seconds), event.event, event.type, 0, 0])
        }
        let timer = try FITActivity(decoding: builder.data()).timerEvents
        let expected: [(UInt32, Bool)] = [
            (0, true), (100, false), (160, true), (300, false), (400, true), (500, false),
        ]
        #expect(
            timer
                == expected.map {
                    FITActivity.TimerEvent(
                        time: RecordingFixtures.date(fit: Self.time + $0), isStart: $1)
                })
    }
}

/// Input that is not FIT, cut short, or refers to undefined messages.
@Suite("FIT decoding errors")
struct BlackBoxFITErrorTests {
    typealias Field = RecordingFITField
    typealias Base = RecordingBase

    nonisolated static func validFile() -> [UInt8] {
        var builder = RecordingFITBuilder()
        builder.fileID()
        builder.define(
            local: 1, global: 20,
            fields: [Field(253, Base.uint32), Field(3, Base.uint8), Field(5, Base.uint32)])
        for index in 0..<5 {
            builder.data(local: 1, [UInt64(1_000_000_000 + index), 120, UInt64(400 * index)])
        }
        builder.define(
            local: 2, global: 21,
            fields: [
                Field(253, Base.uint32), Field(0, Base.enumeration), Field(1, Base.enumeration),
            ])
        builder.data(local: 2, [1_000_000_005, 0, 1])
        return builder.file()
    }

    static func error(decoding bytes: [UInt8]) -> FITError? {
        do {
            _ = try FITActivity(decoding: Data(bytes))
            return nil
        } catch {
            return error
        }
    }

    nonisolated static func nonFITInputs() -> [[UInt8]] {
        var random = RecordingRandom(seed: 99)
        var header = RecordingBytes.encode(14, size: 1) + [0x20, 0x54, 0x08]
        header += RecordingBytes.encode(20, size: 4) + RecordingBytes.ascii(".FIX") + [0, 0]
        return [
            RecordingBytes.ascii("This is a plain text file, not a FIT file at all."),
            RecordingBytes.ascii(#"{"activityId": 1, "activityName": "Morning Run"}"#),
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + random.bytes(40),
            random.bytes(64),
            header + [UInt8](repeating: 0, count: 22),
            Array(StoredZip.archive(name: "1.fit", content: Data(validFile()))),
            [UInt8](repeating: 0, count: 32),
            [UInt8](repeating: 0xFF, count: 32),
        ]
    }

    @Test("Data that is not FIT", arguments: nonFITInputs())
    func notFIT(bytes: [UInt8]) {
        #expect(Self.error(decoding: bytes) == .notFIT)
    }

    @Test("Data too short for a header is rejected", arguments: [0, 1, 5, 11])
    func tooShort(count: Int) {
        let error = Self.error(decoding: Array(Self.validFile().prefix(count)))
        #expect(error == .notFIT || error == .truncated)
    }

    @Test("A cut-off header is rejected", arguments: [12, 13])
    func cutHeader(count: Int) {
        let error = Self.error(decoding: Array(Self.validFile().prefix(count)))
        #expect(error == .notFIT || error == .truncated)
    }

    @Test("Every cut through the messages is truncated")
    func truncatedEverywhere() {
        let file = Self.validFile()
        let dataEnd = file.count - 2
        for count in 14..<dataEnd {
            #expect(
                Self.error(decoding: Array(file.prefix(count))) == .truncated,
                "cut after \(count) of \(file.count) bytes")
        }
    }

    @Test("A header claiming more data than there is is truncated")
    func dataSizeTooLarge() {
        var builder = RecordingFITBuilder()
        builder.fileID()
        #expect(Self.error(decoding: builder.file(extraDataSize: 40)) == .truncated)
    }

    @Test("The complete file decodes")
    func completeFile() throws {
        let fit = try FITActivity(decoding: Data(Self.validFile()))
        #expect(fit.records.count == 5)
        #expect(fit.records.map(\.distance) == [0, 4, 8, 12, 16])
        #expect(fit.timerEvents.count == 1)
    }

    @Test("A data message needs a definition", arguments: 0..<16)
    func undefinedMessage(local: Int) {
        var builder = RecordingFITBuilder()
        builder.define(
            local: UInt8((local + 1) % 16), global: 20, fields: [Field(253, Base.uint32)])
        builder.raw([UInt8(local), 1, 2, 3, 4])
        #expect(Self.error(decoding: builder.file()) == .undefinedMessage(local: local))
    }

    @Test("A compressed timestamp message needs a definition", arguments: 0..<4)
    func undefinedCompressedMessage(local: Int) {
        var builder = RecordingFITBuilder()
        builder.define(
            local: UInt8((local + 1) % 4), global: 20,
            fields: [Field(253, Base.uint32), Field(3, Base.uint8)])
        builder.data(local: UInt8((local + 1) % 4), [1_000_000_000, 100])
        builder.raw([0x80 | UInt8(local << 5) | 3, 120])
        #expect(Self.error(decoding: builder.file()) == .undefinedMessage(local: local))
    }

    @Test("Random messages after a valid header never crash the decoder", arguments: 0..<8)
    func randomBodies(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed) * 7919)
        for _ in 0..<60 {
            var builder = RecordingFITBuilder()
            builder.raw(random.bytes(random.int(0...300)))
            _ = Self.error(decoding: builder.file())
        }
    }

    @Test("Corrupted bytes in a written file never crash the decoder", arguments: 0..<8)
    func corruptedFiles(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed) + 31_337)
        let file = [UInt8](FITWriter.encode(RecordingFixtures.randomActivity(seed: UInt64(seed))))
        for _ in 0..<60 {
            var corrupted = file
            for _ in 0..<random.int(1...4) {
                corrupted[random.int(14...(file.count - 1))] = UInt8(random.int(0...255))
            }
            _ = Self.error(decoding: corrupted)
        }
    }
}
