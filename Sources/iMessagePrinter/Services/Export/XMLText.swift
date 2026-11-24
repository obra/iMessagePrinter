import Foundation

enum XMLText {
    /// Escape text for XML character data.
    static func escape(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x00...0x08).contains(value)
                || value == 0x0B
                || value == 0x0C
                || (0x0E...0x1F).contains(value) {
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

    /// Escape text and turn newlines and tabs into Word run markup.
    static func runs(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var parts: [String] = []
        var current = String()
        for character in normalized {
            switch character {
            case "\n":
                parts.append(escape(current))
                parts.append("<w:br/>")
                current.removeAll(keepingCapacity: true)
            case "\t":
                parts.append(escape(current))
                parts.append("<w:tab/>")
                current.removeAll(keepingCapacity: true)
            default:
                current.append(character)
            }
        }
        parts.append(escape(current))
        return parts.joined()
    }
}
