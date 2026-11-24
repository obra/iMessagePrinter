import Foundation

enum XMLText {
    enum RunSegment: Equatable {
        case text(String)
        case lineBreak
        case tab
    }

    /// Escape text for XML character data.
    static func escape(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x00...0x08).contains(value)
                || value == 0x0B
                || value == 0x0C
                || (0x0E...0x1F).contains(value)
                || value == 0xFFFE
                || value == 0xFFFF {
                continue
            }
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Split text into escaped text and Word line-break/tab run segments.
    static func segments(_ text: String) -> [RunSegment] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var parts: [RunSegment] = []
        var current = String()
        for character in normalized {
            switch character {
            case "\n":
                if !current.isEmpty { parts.append(.text(escape(current))) }
                parts.append(.lineBreak)
                current.removeAll(keepingCapacity: true)
            case "\t":
                if !current.isEmpty { parts.append(.text(escape(current))) }
                parts.append(.tab)
                current.removeAll(keepingCapacity: true)
            default:
                current.append(character)
            }
        }
        if !current.isEmpty { parts.append(.text(escape(current))) }
        return parts
    }
}
