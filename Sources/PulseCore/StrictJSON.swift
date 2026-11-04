import Foundation

/// Foundation validates JSON grammar; this second pass rejects ambiguous duplicate keys
/// (including escaped equivalents) and excessive nesting before schema validation.
enum StrictJSON {
    static func object(_ data: Data) throws -> Any {
        guard data.count <= 131072 else { throw FeedError.invalidData }
        let value = try JSONSerialization.jsonObject(with: data)
        var scanner = KeyScanner(bytes: Array(data))
        try scanner.value(depth: 0)
        return value
    }

    private struct KeyScanner {
        let bytes: [UInt8]
        var index = 0

        mutating func whitespace() {
            while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func string() throws -> String {
            let start = index
            index += 1
            while index < bytes.count {
                if bytes[index] == 92 { index += 2 }
                else if bytes[index] == 34 {
                    index += 1
                    guard let result = try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: .fragmentsAllowed) as? String
                    else { throw FeedError.invalidData }
                    return result
                } else { index += 1 }
            }
            throw FeedError.invalidData
        }

        mutating func value(depth: Int) throws {
            guard depth <= 16 else { throw FeedError.invalidData }
            whitespace()
            guard index < bytes.count else { throw FeedError.invalidData }
            switch bytes[index] {
            case 123:
                index += 1
                whitespace()
                var keys = Set<String>()
                while index < bytes.count && bytes[index] != 125 {
                    guard bytes[index] == 34, keys.insert(try string()).inserted else { throw FeedError.invalidData }
                    whitespace()
                    guard index < bytes.count && bytes[index] == 58 else { throw FeedError.invalidData }
                    index += 1
                    try value(depth: depth + 1)
                    whitespace()
                    if index < bytes.count && bytes[index] == 44 { index += 1; whitespace() }
                    else { break }
                }
                guard index < bytes.count && bytes[index] == 125 else { throw FeedError.invalidData }
                index += 1
            case 91:
                index += 1
                whitespace()
                while index < bytes.count && bytes[index] != 93 {
                    try value(depth: depth + 1)
                    whitespace()
                    if index < bytes.count && bytes[index] == 44 { index += 1 }
                    else { break }
                    whitespace()
                }
                guard index < bytes.count && bytes[index] == 93 else { throw FeedError.invalidData }
                index += 1
            case 34: _ = try string()
            default:
                while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            }
        }
    }
}
