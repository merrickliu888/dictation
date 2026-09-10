import Foundation

/// A tiny TOML reader covering the subset Dictation's `config.toml` needs:
/// comments, `[table]` headers, dotted keys, and single-line string or bare
/// scalar values. Richer TOML (arrays, inline tables, multi-line strings) is
/// rejected with a line number rather than silently misread, so a typo in the
/// config surfaces as a message instead of a mystery binding.
///
/// Values are handed back as the text they were written as; interpreting them
/// is the caller's job (`Shortcut.parse` for the `[shortcuts]` table).
enum TOML {

    struct ParseError: Error, Equatable, CustomStringConvertible {
        let line: Int
        let message: String
        var description: String { "line \(line): \(message)" }
    }

    /// `table name -> key -> value`. The root table is keyed by "".
    typealias Document = [String: [String: String]]

    static func parse(_ text: String) throws -> Document {
        var document: Document = [:]
        var table = ""
        var lineNumber = 0
        for rawLine in text.components(separatedBy: .newlines) {
            lineNumber += 1
            let line = trimmed(rawLine)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                table = try parseTableHeader(line, at: lineNumber)
                if document[table] == nil { document[table] = [:] }
                continue
            }
            let (key, value) = try parseKeyValue(line, at: lineNumber)
            let target = qualify(key: key, in: table)
            if document[target.table]?[target.key] != nil {
                throw ParseError(line: lineNumber, message: "duplicate key '\(target.key)'")
            }
            document[target.table, default: [:]][target.key] = value
        }
        return document
    }

    // MARK: - Lines

    private static func parseTableHeader(_ line: String, at lineNumber: Int) throws -> String {
        if line.hasPrefix("[[") {
            throw ParseError(line: lineNumber, message: "arrays of tables are not supported")
        }
        guard let close = line.firstIndex(of: "]") else {
            throw ParseError(line: lineNumber, message: "unterminated table header")
        }
        let rest = trimmed(String(line[line.index(after: close)...]))
        guard rest.isEmpty || rest.hasPrefix("#") else {
            throw ParseError(line: lineNumber, message: "unexpected text after table header")
        }
        let name = trimmed(String(line[line.index(after: line.startIndex)..<close]))
        guard !name.isEmpty else {
            throw ParseError(line: lineNumber, message: "empty table name")
        }
        return keyPath(name).joined(separator: ".")
    }

    private static func parseKeyValue(_ line: String, at lineNumber: Int) throws -> (key: String, value: String) {
        guard let equals = line.firstIndex(of: "=") else {
            throw ParseError(line: lineNumber, message: "expected 'key = value'")
        }
        let key = trimmed(String(line[line.startIndex..<equals]))
        guard !key.isEmpty else {
            throw ParseError(line: lineNumber, message: "missing key")
        }
        let rawValue = trimmed(String(line[line.index(after: equals)...]))
        guard !rawValue.isEmpty else {
            throw ParseError(line: lineNumber, message: "missing value for '\(key)'")
        }
        return (key, try parseValue(rawValue, at: lineNumber))
    }

    private static func parseValue(_ text: String, at lineNumber: Int) throws -> String {
        guard let first = text.first else {
            throw ParseError(line: lineNumber, message: "missing value")
        }
        guard first == "\"" || first == "'" else {
            // Bare value (numbers, booleans): everything up to a comment.
            guard let hash = text.firstIndex(of: "#") else { return text }
            let value = trimmed(String(text[text.startIndex..<hash]))
            guard !value.isEmpty else {
                throw ParseError(line: lineNumber, message: "missing value")
            }
            return value
        }
        return try parseQuoted(text, quote: first, at: lineNumber)
    }

    private static func parseQuoted(_ text: String, quote: Character, at lineNumber: Int) throws -> String {
        if text.hasPrefix(String(repeating: quote, count: 3)) {
            throw ParseError(line: lineNumber, message: "multi-line strings are not supported")
        }
        var value = ""
        var escaped = false
        var closed = false
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)
            if escaped {
                switch character {
                case "n": value.append("\n")
                case "t": value.append("\t")
                case "r": value.append("\r")
                case "\"": value.append("\"")
                case "'": value.append("'")
                case "\\": value.append("\\")
                default:
                    throw ParseError(line: lineNumber, message: "unsupported escape '\\\(character)'")
                }
                escaped = false
                continue
            }
            // Literal strings ('…') take no escapes, by design.
            if quote == "\"", character == "\\" { escaped = true; continue }
            if character == quote { closed = true; break }
            value.append(character)
        }
        guard closed else {
            throw ParseError(line: lineNumber, message: "unterminated string")
        }
        let rest = trimmed(String(text[index...]))
        guard rest.isEmpty || rest.hasPrefix("#") else {
            throw ParseError(line: lineNumber, message: "unexpected text after value")
        }
        return value
    }

    // MARK: - Keys

    /// Splits `a.b.c` into its segments, unquoting each. Keys containing a
    /// literal dot or '=' are outside the supported subset.
    private static func keyPath(_ key: String) -> [String] {
        let parts = key.split(separator: ".").map { unquote(trimmed(String($0))) }
        return parts.isEmpty ? [unquote(key)] : parts
    }

    /// Resolves a (possibly dotted) key against the table currently open.
    private static func qualify(key: String, in table: String) -> (table: String, key: String) {
        var path = keyPath(key)
        let name = path.removeLast()
        guard !path.isEmpty else { return (table, name) }
        let prefix = path.joined(separator: ".")
        return (table.isEmpty ? prefix : table + "." + prefix, name)
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, let last = text.last,
              first == last, first == "\"" || first == "'"
        else { return text }
        return String(text.dropFirst().dropLast())
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
