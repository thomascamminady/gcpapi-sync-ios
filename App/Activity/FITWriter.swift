import Foundation

/// Writes the parts of a FIT file that ``FITActivity`` reads, for the demo and the tests, and
/// courses of planned routes.
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
        return file(body)
    }

    /// A FIT course along `points`, timed at `speed` metres per second from `start`: a file
    /// Garmin devices follow as a course, copied to one or imported into Garmin Connect.
    static func course(name: String, points: [GeoPoint], speed: Double, start: Date) -> Data {
        var distances = [0.0]
        for (point, next) in zip(points, points.dropFirst()) {
            distances.append((distances.last ?? 0) + point.distance(to: next))
        }
        distances = Array(distances.prefix(points.count))
        let pace = max(speed, 0.5)
        let times = distances.map { seconds(start) + Int64(($0 / pace).rounded()) }
        let end = times.last ?? seconds(start)
        var body = Bytes()
        writeCourseHeader(name: name, start: start, to: &body)
        writeCourseLap(
            points: points, distance: distances.last ?? 0, times: seconds(start)...end,
            to: &body)
        // The timer starts, the points follow, the timer stops.
        body.define(local: 3, global: 21, fields: [(253, 4, 0x86), (0, 1, 0x00), (1, 1, 0x00)])
        body.append(0x03)
        body.put(seconds(start), size: 4)
        body.put(0, size: 1)
        body.put(0, size: 1)
        body.define(
            local: 4, global: 20,
            fields: [(253, 4, 0x86), (0, 4, 0x85), (1, 4, 0x85), (5, 4, 0x86)])
        for (index, point) in points.enumerated() {
            body.append(0x04)
            body.put(times[index], size: 4)
            body.put(semicircles(point.latitude), size: 4)
            body.put(semicircles(point.longitude), size: 4)
            body.put(scaled(distances[index], scale: 100), size: 4)
        }
        body.append(0x03)
        body.put(end, size: 4)
        body.put(0, size: 1)
        body.put(4, size: 1)
        return file(body)
    }

    /// The file ID of a course made by a development tool, and the course's name and sport.
    private static func writeCourseHeader(name: String, start: Date, to body: inout Bytes) {
        body.define(
            local: 0, global: 0,
            fields: [(0, 1, 0x00), (1, 2, 0x84), (2, 2, 0x84), (4, 4, 0x86), (3, 4, 0x8C)])
        body.append(0x00)
        body.put(6, size: 1)
        body.put(255, size: 2)
        body.put(0, size: 2)
        body.put(seconds(start), size: 4)
        body.put(seconds(start) & 0x7FFF_FFFF, size: 4)
        // At most 15 bytes of whole characters and a terminating zero, for running.
        body.define(local: 1, global: 31, fields: [(5, 16, 0x07), (4, 1, 0x00)])
        body.append(0x01)
        var title: [UInt8] = []
        for character in name {
            let bytes = Array(String(character).utf8)
            guard title.count + bytes.count <= 15 else { break }
            title += bytes
        }
        body.bytes += title + Array(repeating: 0, count: 16 - title.count)
        body.put(1, size: 1)
    }

    /// One lap over the whole course, from the first of `times` to the last.
    private static func writeCourseLap(
        points: [GeoPoint], distance: Double, times: ClosedRange<Int64>, to body: inout Bytes
    ) {
        let duration = Double(times.upperBound - times.lowerBound)
        body.define(
            local: 2, global: 19,
            fields: [
                (253, 4, 0x86), (2, 4, 0x86), (3, 4, 0x85), (4, 4, 0x85), (5, 4, 0x85),
                (6, 4, 0x85), (7, 4, 0x86), (8, 4, 0x86), (9, 4, 0x86),
            ])
        body.append(0x02)
        body.put(times.upperBound, size: 4)
        body.put(times.lowerBound, size: 4)
        body.put(points.first.map { semicircles($0.latitude) }, size: 4, invalid: 0x7FFF_FFFF)
        body.put(points.first.map { semicircles($0.longitude) }, size: 4, invalid: 0x7FFF_FFFF)
        body.put(points.last.map { semicircles($0.latitude) }, size: 4, invalid: 0x7FFF_FFFF)
        body.put(points.last.map { semicircles($0.longitude) }, size: 4, invalid: 0x7FFF_FFFF)
        body.put(scaled(duration, scale: 1000), size: 4)
        body.put(scaled(duration, scale: 1000), size: 4)
        body.put(scaled(distance, scale: 100), size: 4)
    }

    /// Degrees in FIT's semicircles.
    private static func semicircles(_ degrees: Double) -> Int64 {
        Int64((degrees * 2_147_483_648.0 / 180).rounded())
    }

    /// The header, `body` and the checksum.
    private static func file(_ body: Bytes) -> Data {
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
