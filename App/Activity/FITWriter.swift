import Foundation

/// Writes the parts of a FIT file that ``FITActivity`` reads, for the demo and the tests.
nonisolated enum FITWriter {
    /// A FIT file of `activity`'s records, laps, sets and timer events.
    static func encode(_ activity: FITActivity) -> Data {
        var body = Bytes()
        writeRecords(activity.records, to: &body)
        writeLaps(activity.laps, to: &body)
        writeSets(activity.sets, to: &body)
        body.define(local: 3, global: 21, fields: [(253, 4, 0x86), (0, 1, 0x00), (1, 1, 0x00)])
        for event in activity.timerEvents {
            body.append(0x03)
            body.put(seconds(event.time), size: 4)
            body.put(0, size: 1)
            body.put(event.isStart ? 0 : 4, size: 1)
        }
        var file = Bytes()
        file.append(14)
        file.append(0x20)
        file.put(2132, size: 2)
        file.put(Int64(body.bytes.count), size: 4)
        file.bytes += Array(".FIT".utf8)
        file.put(Int64(crc(file.bytes)), size: 2)
        file.bytes += body.bytes
        file.put(Int64(crc(file.bytes)), size: 2)
        return Data(file.bytes)
    }

    private static func writeRecords(_ records: [FITActivity.Record], to body: inout Bytes) {
        body.define(
            local: 0, global: 20,
            fields: [
                (253, 4, 0x86), (0, 4, 0x85), (1, 4, 0x85), (78, 4, 0x86), (3, 1, 0x02),
                (4, 1, 0x02), (53, 1, 0x02), (5, 4, 0x86), (73, 4, 0x86), (7, 2, 0x84),
            ])
        let semicircles = 2_147_483_648.0 / 180
        for record in records {
            let whole = record.cadence.map { $0.rounded(.down) }
            body.append(0x00)
            body.put(seconds(record.time), size: 4)
            body.put(
                record.latitude.map { Int64(($0 * semicircles).rounded()) }, size: 4,
                invalid: 0x7FFF_FFFF)
            body.put(
                record.longitude.map { Int64(($0 * semicircles).rounded()) }, size: 4,
                invalid: 0x7FFF_FFFF)
            body.put(scaled(record.altitude, scale: 5, offset: 500), size: 4)
            body.put(record.heartRate.map(Int64.init), size: 1)
            body.put(whole.map { Int64($0) }, size: 1)
            body.put(
                record.cadence.map { Int64((($0 - $0.rounded(.down)) * 128).rounded()) }, size: 1)
            body.put(scaled(record.distance, scale: 100), size: 4)
            body.put(scaled(record.speed, scale: 1000), size: 4)
            body.put(record.power.map(Int64.init), size: 2)
        }
    }

    private static func writeLaps(_ laps: [FITActivity.Lap], to body: inout Bytes) {
        body.define(
            local: 1, global: 19,
            fields: [
                (2, 4, 0x86), (7, 4, 0x86), (8, 4, 0x86), (9, 4, 0x86), (110, 4, 0x86),
                (15, 1, 0x02), (16, 1, 0x02), (21, 2, 0x84), (19, 2, 0x84),
            ])
        for lap in laps {
            body.append(0x01)
            body.put(lap.start.map(seconds), size: 4)
            body.put(scaled(lap.elapsed, scale: 1000), size: 4)
            body.put(scaled(lap.moving, scale: 1000), size: 4)
            body.put(scaled(lap.distance, scale: 100), size: 4)
            body.put(scaled(lap.averageSpeed, scale: 1000), size: 4)
            body.put(lap.averageHeartRate.map(Int64.init), size: 1)
            body.put(lap.maxHeartRate.map(Int64.init), size: 1)
            body.put(lap.ascent.map(Int64.init), size: 2)
            body.put(lap.averagePower.map(Int64.init), size: 2)
        }
    }

    private static func writeSets(_ sets: [FITActivity.ExerciseSet], to body: inout Bytes) {
        body.define(
            local: 2, global: 225,
            fields: [
                (6, 4, 0x86), (0, 4, 0x86), (3, 2, 0x84), (4, 2, 0x84), (5, 1, 0x02), (7, 2, 0x84),
            ])
        for set in sets {
            body.append(0x02)
            body.put(set.start.map(seconds), size: 4)
            body.put(scaled(set.duration, scale: 1000), size: 4)
            body.put(set.repetitions.map(Int64.init), size: 2)
            body.put(scaled(set.weight, scale: 16), size: 2)
            body.put(set.isActive ? 1 : 0, size: 1)
            body.put(set.category.map(Int64.init), size: 2)
        }
    }

    /// FIT's CRC-16.
    static func crc(_ bytes: [UInt8]) -> UInt16 {
        let table: [UInt16] = [
            0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
            0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
        ]
        return bytes.reduce(0) { crc, byte in
            var crc = crc
            for nibble in [byte & 0x0F, byte >> 4] {
                let low = table[Int(crc & 0x0F)]
                crc = (crc >> 4) & 0x0FFF
                crc = crc ^ low ^ table[Int(nibble)]
            }
            return crc
        }
    }

    private static func seconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince(FITActivity.epoch).rounded())
    }

    private static func scaled(_ value: Double?, scale: Double, offset: Double = 0) -> Int64? {
        value.map { Int64((($0 + offset) * scale).rounded()) }
    }

    /// Little-endian bytes with FIT's invalid values for missing ones.
    private struct Bytes {
        var bytes: [UInt8] = []

        mutating func append(_ byte: UInt8) {
            bytes.append(byte)
        }

        mutating func put(_ value: Int64?, size: Int, invalid: UInt64? = nil) {
            let raw =
                value.map { UInt64(bitPattern: $0) } ?? invalid ?? (UInt64.max >> (64 - 8 * size))
            for index in 0..<size {
                bytes.append(UInt8(truncatingIfNeeded: raw >> (8 * UInt64(index))))
            }
        }

        mutating func define(local: UInt8, global: UInt16, fields: [(UInt8, UInt8, UInt8)]) {
            bytes += [0x40 | local, 0, 0]
            put(Int64(global), size: 2)
            bytes.append(UInt8(fields.count))
            for (number, size, type) in fields {
                bytes += [number, size, type]
            }
        }
    }
}
