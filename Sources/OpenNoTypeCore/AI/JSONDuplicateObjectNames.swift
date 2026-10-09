import Foundation

/// Checks only duplicate member names after Foundation has validated JSON syntax.
/// The caller bounds response bytes; quoted values are skipped, never interpreted as keys.
enum JSONDuplicateObjectNames {
    static func areUnique(in validatedData: Data) -> Bool {
        guard let text = String(data: validatedData, encoding: encoding(of: validatedData)) else { return false }
        let bytes = Array(text.utf8)
        struct Frame {
            let isObject: Bool
            var names = Set<Data>()
        }
        var frames: [Frame] = []
        var offset = 0
        while offset < bytes.count {
            switch bytes[offset] {
            case 0x7B, 0x5B: // { or [
                frames.append(Frame(isObject: bytes[offset] == 0x7B))
                guard frames.count <= 512 else { return false }
                offset += 1
            case 0x7D, 0x5D: // } or ]
                guard !frames.isEmpty else { return false }
                frames.removeLast()
                offset += 1
            case 0x22:
                let start = offset
                offset += 1
                while offset < bytes.count {
                    if bytes[offset] == 0x5C { offset += 2; continue }
                    if bytes[offset] == 0x22 { break }
                    offset += 1
                }
                guard offset < bytes.count else { return false }
                offset += 1
                var next = offset
                while next < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[next]) { next += 1 }
                if next < bytes.count, bytes[next] == 0x3A {
                    guard let frame = frames.indices.last, frames[frame].isObject,
                          let name = try? JSONSerialization.jsonObject(
                            with: Data(bytes[start..<offset]), options: [.fragmentsAllowed]) as? String,
                          frames[frame].names.insert(Data(name.utf8)).inserted else { return false }
                }
            default:
                offset += 1
            }
        }
        return frames.isEmpty
    }

    /// Preserve Foundation's UTF-8/16/32 input compatibility, including BOM-less JSON.
    private static func encoding(of data: Data) -> String.Encoding {
        let prefix = Array(data.prefix(4))
        if prefix.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return .utf32BigEndian }
        if prefix.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { return .utf32LittleEndian }
        if prefix.starts(with: [0xFE, 0xFF]) { return .utf16BigEndian }
        if prefix.starts(with: [0xFF, 0xFE]) { return .utf16LittleEndian }
        if prefix.count == 4 {
            if prefix[0] == 0, prefix[1] == 0, prefix[2] == 0 { return .utf32BigEndian }
            if prefix[1] == 0, prefix[2] == 0, prefix[3] == 0 { return .utf32LittleEndian }
            if prefix[0] == 0, prefix[2] == 0 { return .utf16BigEndian }
            if prefix[1] == 0, prefix[3] == 0 { return .utf16LittleEndian }
        }
        return .utf8
    }
}
