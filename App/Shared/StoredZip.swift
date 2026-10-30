import Foundation

/// Writes a zip archive of one uncompressed file, as Garmin's activity downloads are zips;
/// for the demo.
nonisolated enum StoredZip {
    static func archive(name: String, content: Data) -> Data {
        var bytes: [UInt8] = []
        func put(_ value: Int, _ size: Int) {
            for index in 0..<size {
                bytes.append(UInt8(truncatingIfNeeded: value >> (8 * index)))
            }
        }
        let fileName = Array(name.utf8)
        let checksum = Int(crc32([UInt8](content)))
        // Version, flags, method (stored), time, date (1 January 1980), CRC and sizes.
        let entry: [(Int, Int)] = [
            (20, 2), (0, 2), (0, 2), (0, 2), (0x21, 2), (checksum, 4), (content.count, 4),
            (content.count, 4), (fileName.count, 2), (0, 2),
        ]
        put(0x0403_4B50, 4)
        for (value, size) in entry { put(value, size) }
        bytes += fileName
        bytes += content
        let directory = bytes.count
        put(0x0201_4B50, 4)
        put(20, 2)
        for (value, size) in entry { put(value, size) }
        for (value, size) in [(0, 2), (0, 2), (0, 2), (0, 4), (0, 4)] { put(value, size) }
        bytes += fileName
        let directorySize = bytes.count - directory
        put(0x0605_4B50, 4)
        for (value, size) in [
            (0, 2), (0, 2), (1, 2), (1, 2), (directorySize, 4), (directory, 4), (0, 2),
        ] {
            put(value, size)
        }
        return Data(bytes)
    }

    /// The CRC-32 of zip files.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        ~bytes.reduce(UInt32.max) { crc, byte in
            (0..<8).reduce(crc ^ UInt32(byte)) { value, _ in
                value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
            }
        }
    }
}
