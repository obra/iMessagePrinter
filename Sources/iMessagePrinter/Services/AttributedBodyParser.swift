import Foundation

enum AttributedBodyParser {
    /// Extract plain text from an attributedBody typedstream blob
    static func extractText(from data: Data) -> String? {
        // Primary: try NSUnarchiver (handles Apple's typedstream format)
        if let text = extractViaUnarchiver(from: data) {
            return text
        }
        // Fallback: binary scan for string content
        return extractViaBinaryScan(from: data)
    }

    // MARK: - NSUnarchiver approach

    private static func extractViaUnarchiver(from data: Data) -> String? {
        // NSUnarchiver is deprecated but is the correct decoder for typedstream format
        // (not NSKeyedUnarchiver, which is for keyed archives)
        guard let object = NSUnarchiver.unarchiveObject(with: data) else {
            return nil
        }
        if let attrString = object as? NSAttributedString {
            let text = attrString.string
            return text.isEmpty ? nil : text
        }
        if let string = object as? String {
            return string.isEmpty ? nil : string
        }
        return nil
    }

    // MARK: - Binary scan fallback

    private static func extractViaBinaryScan(from data: Data) -> String? {
        // Look for NSString marker in the typedstream, then extract the UTF-8 string after it
        let bytes = [UInt8](data)
        let nsStringMarker: [UInt8] = Array("NSString".utf8)

        // Find the last occurrence of NSString marker (the actual content string)
        var searchStart = 0
        var lastMarkerEnd = -1

        while searchStart < bytes.count - nsStringMarker.count {
            if let idx = findSubsequence(in: bytes, subsequence: nsStringMarker, startingAt: searchStart) {
                lastMarkerEnd = idx + nsStringMarker.count
                searchStart = lastMarkerEnd
            } else {
                break
            }
        }

        guard lastMarkerEnd > 0 else { return nil }

        // After the marker, skip class definition bytes until we find a length byte
        var pos = lastMarkerEnd
        // Skip over type info bytes
        while pos < bytes.count && (bytes[pos] == 0x84 || bytes[pos] == 0x85 || bytes[pos] == 0x86 || bytes[pos] >= 0x90) {
            pos += 1
        }

        // Try to read a string length and extract the text
        if pos < bytes.count {
            let length: Int
            if bytes[pos] == 0x81, pos + 2 < bytes.count {
                // 16-bit length
                length = Int(bytes[pos + 1]) | (Int(bytes[pos + 2]) << 8)
                pos += 3
            } else if bytes[pos] < 0x80 {
                // Single byte length
                length = Int(bytes[pos])
                pos += 1
            } else {
                return nil
            }

            guard pos + length <= bytes.count, length > 0 else { return nil }
            let textData = Data(bytes[pos..<(pos + length)])
            return String(data: textData, encoding: .utf8)
        }

        return nil
    }

    private static func findSubsequence(in data: [UInt8], subsequence: [UInt8], startingAt: Int) -> Int? {
        guard !subsequence.isEmpty else { return startingAt }
        let end = data.count - subsequence.count
        guard startingAt <= end else { return nil }

        for i in startingAt...end {
            var match = true
            for j in 0..<subsequence.count {
                if data[i + j] != subsequence[j] {
                    match = false
                    break
                }
            }
            if match { return i }
        }
        return nil
    }
}
