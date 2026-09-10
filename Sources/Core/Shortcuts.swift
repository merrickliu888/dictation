import Foundation

// MARK: - Modifiers

/// The modifiers a shortcut can require. Mirrors the AppKit and Quartz flags
/// without depending on either, so the config layer stays unit-testable.
struct ShortcutModifiers: OptionSet, Hashable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let command = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)

    /// Shift alone can't carry a shortcut — it is part of ordinary typing.
    var hasNonShiftModifier: Bool {
        !intersection([.control, .option, .command]).isEmpty
    }

    /// Symbol order matches the hints Minimal shows (⌃`, ⌘⇧D).
    var display: String {
        var symbols = ""
        if contains(.control) { symbols += "⌃" }
        if contains(.option) { symbols += "⌥" }
        if contains(.command) { symbols += "⌘" }
        if contains(.shift) { symbols += "⇧" }
        return symbols
    }

    static func named(_ token: String) -> ShortcutModifiers? {
        switch token {
        case "cmd", "command", "⌘": return .command
        case "opt", "option", "alt", "⌥": return .option
        case "ctrl", "control", "⌃": return .control
        case "shift", "⇧": return .shift
        default: return nil
        }
    }
}

// MARK: - Shortcut

enum ShortcutParseError: Error, Equatable, CustomStringConvertible {
    case empty
    case missingKey
    case multipleKeys(String, String)
    case unknownKey(String)
    case mismatchedTaps(String, String)
    case tooManyTaps

    var description: String {
        switch self {
        case .empty: return "empty shortcut"
        case .missingKey: return "no key, only modifiers"
        case .multipleKeys(let first, let second): return "two keys ('\(first)' and '\(second)')"
        case .unknownKey(let key): return "unknown key '\(key)'"
        case .mismatchedTaps(let first, let second):
            return "a double tap repeats one shortcut, not '\(first)' then '\(second)'"
        case .tooManyTaps: return "more than two presses"
        }
    }
}

/// A key plus its modifiers, identified by virtual key code so it survives
/// keyboard-layout differences.
struct Shortcut: Equatable, Hashable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers

    init(_ keyCode: UInt16, _ modifiers: ShortcutModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// How the shortcut is spelled in the on-screen hints, e.g. "⌃Space".
    var display: String {
        modifiers.display + (Self.keysByCode[keyCode]?.display ?? "key \(keyCode)")
    }

    /// Keys that are themselves modifiers — fn, ⌥, ⌘… — arrive as flag
    /// changes rather than key presses, and type nothing on their own.
    var isModifierKey: Bool { Self.keysByCode[keyCode]?.isModifier ?? false }

    var isFunctionKey: Bool { Self.keysByCode[keyCode]?.isFunction ?? false }

    /// Whether the shortcut can be bound without swallowing ordinary typing:
    /// it carries ⌘, ⌥ or ⌃, or its key types nothing by itself.
    var isBindable: Bool {
        modifiers.hasNonShiftModifier || isModifierKey || isFunctionKey
    }

    /// Reads spellings like "fn", "ctrl+space", "⌥Space" or "rightoption".
    static func parse(_ text: String) throws -> Shortcut {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ShortcutParseError.empty }

        var modifiers: ShortcutModifiers = []
        var key: String?
        for rawToken in cleaned.split(separator: "+", omittingEmptySubsequences: false) {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty else { throw ShortcutParseError.unknownKey("+") }
            if let modifier = ShortcutModifiers.named(token) {
                modifiers.insert(modifier)
                continue
            }
            // Peel leading modifier symbols so "⌘⇧D" parses as one token.
            var remainder = Substring(token)
            while let first = remainder.first, let modifier = ShortcutModifiers.named(String(first)) {
                modifiers.insert(modifier)
                remainder = remainder.dropFirst()
            }
            guard !remainder.isEmpty else { continue }
            if let key { throw ShortcutParseError.multipleKeys(key, String(remainder)) }
            key = String(remainder)
        }

        guard let key else { throw ShortcutParseError.missingKey }
        if let keyCode = Self.codesByName[key] { return Shortcut(keyCode, modifiers) }
        // "key<code>" names any key the table doesn't — how the settings
        // window records one it has no better spelling for.
        if key.hasPrefix("key"), let keyCode = UInt16(key.dropFirst(3)) {
            return Shortcut(keyCode, modifiers)
        }
        throw ShortcutParseError.unknownKey(key)
    }
}

// MARK: - Key table

extension Shortcut {

    /// One physical key: the virtual key code AppKit and Quartz report, the
    /// spellings accepted in the config file, the character it types on a
    /// US layout, and how it is drawn in a hint.
    struct KeyDefinition {
        let code: UInt16
        let names: [String]
        let character: Character?
        let display: String
        let isModifier: Bool
        let isFunction: Bool

        init(
            _ code: UInt16, _ names: [String], character: Character? = nil, display: String? = nil,
            isModifier: Bool = false, isFunction: Bool = false
        ) {
            self.code = code
            self.names = names
            self.character = character
            self.display = display ?? names[0].uppercased()
            self.isModifier = isModifier
            self.isFunction = isFunction
        }
    }

    static let keys: [KeyDefinition] = {
        let letters: [(Character, UInt16)] = [
            ("a", 0), ("b", 11), ("c", 8), ("d", 2), ("e", 14), ("f", 3), ("g", 5),
            ("h", 4), ("i", 34), ("j", 38), ("k", 40), ("l", 37), ("m", 46), ("n", 45),
            ("o", 31), ("p", 35), ("q", 12), ("r", 15), ("s", 1), ("t", 17), ("u", 32),
            ("v", 9), ("w", 13), ("x", 7), ("y", 16), ("z", 6),
        ]
        let digits: [(Character, UInt16)] = [
            ("0", 29), ("1", 18), ("2", 19), ("3", 20), ("4", 21),
            ("5", 23), ("6", 22), ("7", 26), ("8", 28), ("9", 25),
        ]
        var definitions: [KeyDefinition] = []
        for (character, code) in letters + digits {
            definitions.append(KeyDefinition(code, [String(character)], character: character))
        }
        definitions += [
            KeyDefinition(27, ["-", "minus"], character: "-", display: "-"),
            KeyDefinition(24, ["=", "equal"], character: "=", display: "="),
            KeyDefinition(33, ["[", "leftbracket"], character: "[", display: "["),
            KeyDefinition(30, ["]", "rightbracket"], character: "]", display: "]"),
            KeyDefinition(42, ["\\", "backslash"], character: "\\", display: "\\"),
            KeyDefinition(41, [";", "semicolon"], character: ";", display: ";"),
            KeyDefinition(39, ["'", "quote", "apostrophe"], character: "'", display: "'"),
            KeyDefinition(43, [",", "comma"], character: ",", display: ","),
            KeyDefinition(47, [".", "period", "dot"], character: ".", display: "."),
            KeyDefinition(44, ["/", "slash"], character: "/", display: "/"),
            KeyDefinition(50, ["`", "grave", "backtick"], character: "`", display: "`"),
            KeyDefinition(49, ["space"], character: " ", display: "Space"),
            KeyDefinition(48, ["tab"], display: "Tab"),
            KeyDefinition(36, ["return", "enter"], display: "⏎"),
            KeyDefinition(53, ["escape", "esc"], display: "⎋"),
            KeyDefinition(51, ["delete", "backspace"], display: "⌫"),
            KeyDefinition(117, ["forwarddelete", "forward_delete"], display: "⌦"),
            KeyDefinition(123, ["left", "leftarrow"], display: "←"),
            KeyDefinition(124, ["right", "rightarrow"], display: "→"),
            KeyDefinition(125, ["down", "downarrow"], display: "↓"),
            KeyDefinition(126, ["up", "uparrow"], display: "↑"),
            KeyDefinition(115, ["home"], display: "↖"),
            KeyDefinition(119, ["end"], display: "↘"),
            KeyDefinition(116, ["pageup", "page_up"], display: "⇞"),
            KeyDefinition(121, ["pagedown", "page_down"], display: "⇟"),
        ]
        let functionKeys: [(Int, UInt16)] = [
            (1, 122), (2, 120), (3, 99), (4, 118), (5, 96), (6, 97), (7, 98), (8, 100),
            (9, 101), (10, 109), (11, 103), (12, 111), (13, 105), (14, 107), (15, 113),
            (16, 106), (17, 64), (18, 79), (19, 80), (20, 90),
        ]
        for (number, code) in functionKeys {
            definitions.append(KeyDefinition(code, ["f\(number)"], display: "F\(number)", isFunction: true))
        }
        // Modifier keys as keys in their own right. Left and right are
        // distinct key codes, so "rightoption" can be a dictation key while
        // the left one keeps typing accents.
        definitions += [
            KeyDefinition(63, ["fn", "globe", "function"], display: "fn", isModifier: true),
            KeyDefinition(58, ["leftoption", "leftopt", "leftalt"], display: "Left ⌥", isModifier: true),
            KeyDefinition(61, ["rightoption", "rightopt", "rightalt"], display: "Right ⌥", isModifier: true),
            KeyDefinition(55, ["leftcommand", "leftcmd"], display: "Left ⌘", isModifier: true),
            KeyDefinition(54, ["rightcommand", "rightcmd"], display: "Right ⌘", isModifier: true),
            KeyDefinition(59, ["leftcontrol", "leftctrl"], display: "Left ⌃", isModifier: true),
            KeyDefinition(62, ["rightcontrol", "rightctrl"], display: "Right ⌃", isModifier: true),
            KeyDefinition(56, ["leftshift"], display: "Left ⇧", isModifier: true),
            KeyDefinition(60, ["rightshift"], display: "Right ⇧", isModifier: true),
        ]
        return definitions
    }()

    static let codesByName: [String: UInt16] = {
        var table: [String: UInt16] = [:]
        for key in Shortcut.keys {
            for name in key.names { table[name] = key.code }
        }
        return table
    }()

    static let keysByCode: [UInt16: KeyDefinition] = {
        var table: [UInt16: KeyDefinition] = [:]
        for key in Shortcut.keys { table[key.code] = key }
        return table
    }()
}

// MARK: - Trigger

/// A shortcut and how many times it must be pressed: "fn" is one press,
/// "fn fn" a double tap.
struct Trigger: Equatable, Hashable {
    let shortcut: Shortcut
    let taps: Int

    init(_ shortcut: Shortcut, taps: Int = 1) {
        self.shortcut = shortcut
        self.taps = max(1, min(2, taps))
    }

    var isDoubleTap: Bool { taps == 2 }

    /// e.g. "fn" or "fn fn".
    var display: String {
        isDoubleTap ? "\(shortcut.display) \(shortcut.display)" : shortcut.display
    }

    /// Reads "fn", "ctrl+space" or "fn fn". Whitespace only separates
    /// presses, so "cmd + space" is still one shortcut.
    static func parse(_ text: String) throws -> Trigger {
        let compact = text.replacingOccurrences(
            of: #"\s*\+\s*"#, with: "+", options: .regularExpression)
        let parts = compact.split(whereSeparator: { $0.isWhitespace })
        guard let first = parts.first else { throw ShortcutParseError.empty }
        let shortcut = try Shortcut.parse(String(first))
        switch parts.count {
        case 1:
            return Trigger(shortcut)
        case 2:
            let second = try Shortcut.parse(String(parts[1]))
            guard second == shortcut else {
                throw ShortcutParseError.mismatchedTaps(String(first), String(parts[1]))
            }
            return Trigger(shortcut, taps: 2)
        default:
            throw ShortcutParseError.tooManyTaps
        }
    }
}

// MARK: - Actions

/// Every shortcut a user can rebind. The raw value is the key used under
/// `[shortcuts]` in config.toml.
enum ShortcutAction: String, CaseIterable {
    case hold = "hold"
    case toggle = "toggle"

    var defaultTrigger: Trigger {
        switch self {
        case .hold: return Trigger(Shortcut(63))            // fn
        case .toggle: return Trigger(Shortcut(63), taps: 2) // fn fn
        }
    }

    /// Only the toggle can be a double tap: a hold starts on the press.
    var allowsDoubleTap: Bool { self == .toggle }

    var summary: String {
        switch self {
        case .hold: return "hold to dictate, release to insert"
        case .toggle: return "dictate hands-free; press once more to stop"
        }
    }
}

// MARK: - Config

/// The shortcut table the app runs on: defaults, overridden by whatever a
/// user's `config.toml` binds. Always complete — an action the file doesn't
/// mention, or binds badly, keeps its default.
struct ShortcutConfig {
    private(set) var bindings: [ShortcutAction: Trigger]
    /// Problems found while loading, surfaced in Settings and the log.
    private(set) var warnings: [String] = []
    /// The file the overrides came from; nil when none was found.
    private(set) var source: URL?

    static let defaults = ShortcutConfig()

    init() {
        bindings = Dictionary(
            uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultTrigger) })
    }

    subscript(action: ShortcutAction) -> Trigger {
        bindings[action] ?? action.defaultTrigger
    }

    // MARK: Parsing

    static func parse(toml text: String, source: URL? = nil) -> ShortcutConfig {
        var config = ShortcutConfig()
        config.source = source
        let document: TOML.Document
        do {
            document = try TOML.parse(text)
        } catch {
            config.warnings.append("config is not valid TOML (\(error)); using default shortcuts")
            return config
        }

        for table in document.keys.sorted() where table != "shortcuts" {
            guard let entries = document[table], !entries.isEmpty else { continue }
            config.warnings.append(
                "ignoring unknown section '\(table.isEmpty ? "top level" : "[\(table)]")'")
        }

        for (name, value) in (document["shortcuts"] ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let action = ShortcutAction(rawValue: name) else {
                config.warnings.append("ignoring unknown shortcut '\(name)'")
                continue
            }
            let fallback = "keeping \(action.defaultTrigger.display)"
            do {
                let trigger = try Trigger.parse(value)
                guard trigger.shortcut.isBindable else {
                    config.warnings.append(
                        "\(name) = \"\(value)\" needs ⌘, ⌥ or ⌃, or a key that types nothing (fn, F5…); \(fallback)")
                    continue
                }
                guard !trigger.isDoubleTap || action.allowsDoubleTap else {
                    config.warnings.append(
                        "\(name) = \"\(value)\" can't be a double tap — a hold starts on the first press; \(fallback)")
                    continue
                }
                config.bindings[action] = trigger
            } catch {
                config.warnings.append("\(name) = \"\(value)\" is not a shortcut (\(error)); \(fallback)")
            }
        }

        // The same single press for both isn't fatal — the toggle takes it —
        // but it is never what the user meant, so say so.
        if config[.hold].shortcut == config[.toggle].shortcut, !config[.toggle].isDoubleTap {
            config.warnings.append(
                "hold and toggle are both \(config[.hold].display); the toggle wins, so there is no hold-to-dictate")
        }
        return config
    }

    // MARK: Loading

    /// Where a user's config file is expected to live.
    static func userConfigPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> URL {
        let configHome = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? home + "/.config"
        return URL(fileURLWithPath: configHome + "/dictation/config.toml")
    }

    /// Candidates in priority order; the first one that exists is used.
    static func searchPaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> [URL] {
        var paths: [URL] = []
        if let explicit = environment["DICTATION_CONFIG"], !explicit.isEmpty {
            paths.append(URL(fileURLWithPath: expandingTilde(explicit, home: home)))
        }
        paths.append(userConfigPath(environment: environment, home: home))
        paths.append(URL(fileURLWithPath: home + "/Library/Application Support/Dictation/config.toml"))
        return paths
    }

    private static func expandingTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst()) }
        return path
    }

    static func load(searchPaths: [URL] = ShortcutConfig.searchPaths()) -> ShortcutConfig {
        for url in searchPaths {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                var config = ShortcutConfig()
                config.source = url
                config.warnings = ["\(url.path) could not be read; using default shortcuts"]
                return config
            }
            return parse(toml: text, source: url)
        }
        return ShortcutConfig()
    }
}

// MARK: - Seeding

extension Shortcut {

    /// How this shortcut is written in config.toml, e.g. "ctrl+space".
    /// Modifier order matches the on-screen hints (⌃⌥⌘⇧) so the two spellings
    /// read the same way round.
    var configSpelling: String {
        var tokens: [String] = []
        if modifiers.contains(.control) { tokens.append("ctrl") }
        if modifiers.contains(.option) { tokens.append("opt") }
        if modifiers.contains(.command) { tokens.append("cmd") }
        if modifiers.contains(.shift) { tokens.append("shift") }
        tokens.append(Self.keysByCode[keyCode]?.names[0] ?? "key\(keyCode)")
        return tokens.joined(separator: "+")
    }
}

extension Trigger {

    /// How this trigger is written in config.toml, e.g. "fn fn".
    var configSpelling: String {
        isDoubleTap ? "\(shortcut.configSpelling) \(shortcut.configSpelling)" : shortcut.configSpelling
    }
}

extension ShortcutConfig {

    /// The file Dictation writes to `userConfigPath()` on first launch: every
    /// action, its default, and the whole format, with each binding commented
    /// out. Editing shortcuts then needs no other reference.
    ///
    /// The bindings are generated from the defaults rather than typed out, so
    /// the file can never claim a default the app doesn't actually use. They
    /// ship commented because an uncommented line pins that binding: a later
    /// change to a default would never reach anyone holding a seeded file.
    static var template: String {
        let actions = ShortcutAction.allCases
        let nameWidth = actions.map(\.rawValue.count).max() ?? 0
        let bindingWidth = actions.map { $0.defaultTrigger.configSpelling.count + 2 }.max() ?? 0

        func line(_ action: ShortcutAction) -> String {
            let name = action.rawValue.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            let binding = "\"\(action.defaultTrigger.configSpelling)\""
                .padding(toLength: bindingWidth, withPad: " ", startingAt: 0)
            return "# \(name) = \(binding)  # \(action.summary)"
        }

        let bindings = actions.map(line).joined(separator: "\n")

        return """
        # Dictation shortcuts. Every line below is commented out, so Dictation is
        # running its defaults. Uncomment a line and edit it to rebind that action;
        # leave a line commented and that action keeps its default, even if that
        # default changes in a later release.
        #
        # Format: modifiers and a key joined by "+", e.g. "ctrl+space". Modifiers are
        # cmd/command, opt/option/alt, ctrl/control and shift (symbols work too, so
        # "⌃Space" is the same shortcut). Keys are letters, digits, f1–f20, punctuation
        # ("," "." "/" "`" "-" "=" "[" "]" ";" "'" "\\"), or a name: space, tab, return,
        # escape, delete, forwarddelete, left, right, up, down, home, end, pageup,
        # pagedown. A modifier key on its own works as well: fn (the 🌐 key),
        # leftoption, rightoption, leftcommand, rightcommand, leftcontrol,
        # rightcontrol, leftshift, rightshift.
        #
        # Write a shortcut twice ("fn fn") to require a double tap. Only toggle can be
        # a double tap; hold always starts on the first press.
        #
        # A shortcut needs at least one of cmd, opt or ctrl unless its key is a
        # modifier or function key — anything else would swallow ordinary typing.
        # Entries Dictation can't use are ignored (the default is kept) and explained
        # in the settings window.
        #
        # Edits are picked up with "Reload Config" in the menu bar — the microphone in
        # the status bar — so there is no need to restart the app. Changing a
        # shortcut in the settings window writes to this file too.

        [shortcuts]

        \(bindings)

        """
    }

    /// Writes `template` to `destination` when no config file exists anywhere
    /// in `searchPaths`, so a fresh install has something to edit. Returns the
    /// file it wrote, or nil when it left the disk alone.
    @discardableResult
    static func seedUserConfigIfMissing(
        searchPaths: [URL] = ShortcutConfig.searchPaths(),
        destination: URL = ShortcutConfig.userConfigPath()
    ) -> URL? {
        // Any existing config counts, not just one at `destination`: seeding
        // alongside a $DICTATION_CONFIG the user already has would leave a
        // second file that is never read.
        let manager = FileManager.default
        if searchPaths.contains(where: { manager.fileExists(atPath: $0.path) }) { return nil }
        do {
            try manager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try template.write(to: destination, atomically: true, encoding: .utf8)
            return destination
        } catch {
            // A read-only home directory is no reason to fail launch.
            NSLog("Shortcuts: could not write %@ (%@)", destination.path, String(describing: error))
            return nil
        }
    }
}

// MARK: - Rebinding

extension ShortcutConfig {

    /// `text` with `action` bound to `trigger`: the action's line under
    /// `[shortcuts]` — commented out or not — is replaced, or one is added at
    /// the end of that table (or a new table) when there is none. Everything
    /// else in the file, comments included, is kept as written.
    static func rebinding(_ action: ShortcutAction, to trigger: Trigger, in text: String) -> String {
        let binding = "\(action.rawValue) = \"\(trigger.configSpelling)\"  # \(action.summary)"
        var lines = text.components(separatedBy: "\n")

        var header: Int?
        var end: Int?
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if header != nil {
                    end = index
                    break
                }
                if tableName(line) == "shortcuts" { header = index }
                continue
            }
            guard header != nil else { continue }
            var body = Substring(line)
            if body.hasPrefix("#") {
                body = body.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
            }
            guard let equals = body.firstIndex(of: "=") else { continue }
            if body[..<equals].trimmingCharacters(in: .whitespaces) == action.rawValue {
                lines[index] = binding
                return lines.joined(separator: "\n")
            }
        }

        guard let header else {
            var result = text
            if !result.isEmpty, !result.hasSuffix("\n") { result += "\n" }
            if !result.isEmpty { result += "\n" }
            return result + "[shortcuts]\n\(binding)\n"
        }
        // Add to the table, ahead of the blank lines that separate it from
        // whatever follows.
        var insertAt = end ?? lines.count
        while insertAt > header + 1, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertAt -= 1
        }
        lines.insert(binding, at: insertAt)
        return lines.joined(separator: "\n")
    }

    private static func tableName(_ line: String) -> String {
        guard let close = line.firstIndex(of: "]") else { return "" }
        return line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces)
    }

    /// Persists a binding to the config file in use (or the default path when
    /// there is none yet, seeded from the template so the documentation comes
    /// along). Returns the file written.
    @discardableResult
    static func rebind(
        _ action: ShortcutAction, to trigger: Trigger,
        at destination: URL? = nil
    ) throws -> URL {
        let url = destination ?? Shortcuts.config.source ?? userConfigPath()
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? template
        let updated = rebinding(action, to: trigger, in: existing)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Process-wide bindings

/// The one table every key handler and hint reads. Loaded at launch and on
/// demand from the menu bar, so editing config.toml doesn't need a restart.
enum Shortcuts {
    private(set) static var config = ShortcutConfig.defaults

    static subscript(action: ShortcutAction) -> Trigger { config[action] }

    /// Hint text for an action, e.g. "fn fn".
    static func display(_ action: ShortcutAction) -> String { config[action].display }

    @discardableResult
    static func reload() -> ShortcutConfig {
        config = ShortcutConfig.load()
        for warning in config.warnings { NSLog("Shortcuts: %@", warning) }
        return config
    }
}
