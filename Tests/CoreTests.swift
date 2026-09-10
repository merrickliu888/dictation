import Foundation

// Minimal hand-rolled test harness (no XCTest in a plain swiftc build).
var failureCount = 0
var testCount = 0

func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    testCount += 1
    if !condition {
        failureCount += 1
        print("FAIL [\((file as NSString).lastPathComponent):\(line)] \(message)")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    expect(a == b, "\(message) — expected \(b), got \(a)", file: file, line: line)
}

let fn = Shortcut(63)
let ctrlSpace = Shortcut(49, [.control])
let f5 = Shortcut(96)

// MARK: - TOML

func testTOMLParsing() {
    let document = try! TOML.parse("""
        # comment
        top = "level"

        [shortcuts]
        hold = "fn"      # trailing comment
        toggle = 'fn fn'
        [other.nested]
        key.sub = 3
        """)
    expectEqual(document[""]?["top"], "level", "root table")
    expectEqual(document["shortcuts"]?["hold"], "fn", "basic string with comment")
    expectEqual(document["shortcuts"]?["toggle"], "fn fn", "literal string")
    expectEqual(document["other.nested.key"]?["sub"], "3", "dotted key inside dotted table")

    expectEqual(try! TOML.parse("k = \"a\\\"b\\n\"")[""]?["k"], "a\"b\n", "escapes in basic strings")
    expectEqual(try! TOML.parse("k = 'a\\b'")[""]?["k"], "a\\b", "no escapes in literal strings")

    func error(_ text: String) -> TOML.ParseError? {
        do { _ = try TOML.parse(text) } catch let error as TOML.ParseError { return error } catch {}
        return nil
    }
    expectEqual(error("k = \"open")?.message, "unterminated string", "unterminated string")
    expectEqual(error("k = \"\"\"multi\"\"\"")?.line, 1, "multi-line strings are rejected with a line number")
    expectEqual(error("[shortcuts]\nk = 1\nk = 2")?.message, "duplicate key 'k'", "duplicate key")
    expectEqual(error("[[t]]")?.message, "arrays of tables are not supported", "array tables")
}

// MARK: - Shortcuts

func testShortcutParsing() {
    expectEqual(try! Shortcut.parse("fn"), fn, "fn by name")
    expectEqual(try! Shortcut.parse("Globe"), fn, "globe alias, case-insensitive")
    expectEqual(try! Shortcut.parse("ctrl+space"), ctrlSpace, "modifier + key")
    expectEqual(try! Shortcut.parse("⌃Space"), ctrlSpace, "symbol spelling")
    expectEqual(try! Shortcut.parse("cmd+shift+d"), Shortcut(2, [.command, .shift]), "two modifiers")
    expectEqual(try! Shortcut.parse("rightoption"), Shortcut(61), "sided modifier key")
    expectEqual(try! Shortcut.parse("f5"), f5, "function key")
    expectEqual(try! Shortcut.parse("key37"), Shortcut(37), "raw key code spelling")
    expectEqual(try! Shortcut.parse("cmd+key37"), Shortcut(37, [.command]), "raw key code with modifier")

    expectEqual(fn.display, "fn", "fn display")
    expectEqual(ctrlSpace.display, "⌃Space", "chord display")
    expectEqual(Shortcut(61).display, "Right ⌥", "sided modifier display")
    expectEqual(Shortcut(200).display, "key 200", "unknown key display")
    expectEqual(fn.configSpelling, "fn", "fn spelling")
    expectEqual(ctrlSpace.configSpelling, "ctrl+space", "chord spelling")
    expectEqual(Shortcut(200, [.option]).configSpelling, "opt+key200", "unknown key spelling round-trips")
    expectEqual(try! Shortcut.parse(Shortcut(200, [.option]).configSpelling), Shortcut(200, [.option]), "round trip")

    func error(_ text: String) -> ShortcutParseError? {
        do { _ = try Shortcut.parse(text) } catch let error as ShortcutParseError { return error } catch {}
        return nil
    }
    expectEqual(error(""), .empty, "empty")
    expectEqual(error("cmd"), .missingKey, "modifiers only")
    expectEqual(error("cmd+"), .unknownKey("+"), "dangling plus")
    expectEqual(error("fn+space"), .multipleKeys("fn", "space"), "fn is a key, not a modifier")
    expectEqual(error("cmd+bogus"), .unknownKey("bogus"), "unknown key")
}

func testShortcutBindability() {
    expect(fn.isBindable, "fn alone types nothing")
    expect(Shortcut(61).isBindable, "right option alone")
    expect(f5.isBindable, "function key alone")
    expect(ctrlSpace.isBindable, "chord with control")
    expect(!Shortcut(49).isBindable, "space alone would swallow typing")
    expect(!Shortcut(0, [.shift]).isBindable, "shift+a is typing")
    expect(fn.isModifierKey && !ctrlSpace.isModifierKey, "modifier key flag")
}

func testTriggerParsing() {
    expectEqual(try! Trigger.parse("fn"), Trigger(fn), "single press")
    expectEqual(try! Trigger.parse("fn fn"), Trigger(fn, taps: 2), "double tap")
    expectEqual(try! Trigger.parse("  fn   fn "), Trigger(fn, taps: 2), "whitespace tolerant")
    expectEqual(try! Trigger.parse("ctrl + space"), Trigger(ctrlSpace), "spaces around + are not taps")
    expectEqual(try! Trigger.parse("ctrl+space ctrl+space"), Trigger(ctrlSpace, taps: 2), "double-tap chord")

    expectEqual(Trigger(fn, taps: 2).display, "fn fn", "double display")
    expectEqual(Trigger(fn, taps: 2).configSpelling, "fn fn", "double spelling")
    expectEqual(Trigger(ctrlSpace).configSpelling, "ctrl+space", "single spelling")
    expectEqual(Trigger(fn, taps: 5).taps, 2, "taps clamp to two")

    func error(_ text: String) -> ShortcutParseError? {
        do { _ = try Trigger.parse(text) } catch let error as ShortcutParseError { return error } catch {}
        return nil
    }
    expectEqual(error("fn f5"), .mismatchedTaps("fn", "f5"), "different keys")
    expectEqual(error("fn fn fn"), .tooManyTaps, "triple tap")
    expectEqual(error(""), .empty, "empty trigger")
}

func testShortcutConfigOverrides() {
    let config = ShortcutConfig.parse(toml: """
        [shortcuts]
        hold = "rightoption"
        toggle = "ctrl+space"
        """)
    expectEqual(config[.hold], Trigger(Shortcut(61)), "hold rebound")
    expectEqual(config[.toggle], Trigger(ctrlSpace), "toggle can be a single press")
    expect(config.warnings.isEmpty, "clean config has no warnings: \(config.warnings)")

    let partial = ShortcutConfig.parse(toml: "[shortcuts]\ntoggle = \"f5 f5\"\n")
    expectEqual(partial[.hold], ShortcutAction.hold.defaultTrigger, "unmentioned action keeps its default")
    expectEqual(partial[.toggle], Trigger(f5, taps: 2), "double-tap toggle on another key")

    expectEqual(ShortcutConfig.parse(toml: "").bindings, ShortcutConfig.defaults.bindings, "empty file is defaults")
    expectEqual(ShortcutConfig.defaults[.hold], Trigger(fn), "default hold is fn")
    expectEqual(ShortcutConfig.defaults[.toggle], Trigger(fn, taps: 2), "default toggle is a double tap of fn")
}

func testShortcutConfigRejectsBadEntries() {
    let config = ShortcutConfig.parse(toml: """
        [shortcuts]
        hold = "fn fn"
        toggle = "space"
        launch = "cmd+l"
        [other]
        x = 1
        """)
    expectEqual(config[.hold], Trigger(fn), "a double-tap hold keeps the default")
    expectEqual(config[.toggle], Trigger(fn, taps: 2), "an unbindable key keeps the default")
    expectEqual(config.warnings.count, 4, "one warning each: \(config.warnings)")
    expect(config.warnings.contains { $0.contains("can't be a double tap") }, "explains the hold rule")
    expect(config.warnings.contains { $0.contains("needs ⌘, ⌥ or ⌃") }, "explains the typing rule")
    expect(config.warnings.contains { $0.contains("unknown shortcut 'launch'") }, "unknown action")
    expect(config.warnings.contains { $0.contains("[other]") }, "unknown section")

    let clash = ShortcutConfig.parse(toml: "[shortcuts]\nhold = \"ctrl+space\"\ntoggle = \"ctrl+space\"\n")
    expect(clash.warnings.contains { $0.contains("the toggle wins") }, "same single press for both is flagged")

    let sameKeyDouble = ShortcutConfig.parse(toml: "[shortcuts]\nhold = \"fn\"\ntoggle = \"fn fn\"\n")
    expect(sameKeyDouble.warnings.isEmpty, "hold and a double tap on the same key is the normal setup")

    let garbage = ShortcutConfig.parse(toml: "[shortcuts\nhold = 1")
    expectEqual(garbage.bindings, ShortcutConfig.defaults.bindings, "invalid TOML falls back to defaults")
    expect(garbage.warnings.first?.contains("not valid TOML") == true, "and says why")

    let typo = ShortcutConfig.parse(toml: "[shortcuts]\nhold = \"cmd\"\n")
    expect(typo.warnings.first?.contains("no key, only modifiers") == true, "parse errors are explained")
}

func testShortcutConfigLoading() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("dictation-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = directory.appendingPathComponent("first.toml")
    let second = directory.appendingPathComponent("second.toml")
    try! "[shortcuts]\nhold = \"f5\"\n".write(to: second, atomically: true, encoding: .utf8)

    let loaded = ShortcutConfig.load(searchPaths: [first, second])
    expectEqual(loaded[.hold], Trigger(f5), "first existing file wins")
    expectEqual(loaded.source, second, "source is the file used")
    expect(ShortcutConfig.load(searchPaths: [first]).source == nil, "no file → no source")

    let paths = ShortcutConfig.searchPaths(
        environment: ["DICTATION_CONFIG": "~/custom.toml", "XDG_CONFIG_HOME": "/xdg"], home: "/home/me")
    expectEqual(paths.map(\.path), [
        "/home/me/custom.toml",
        "/xdg/dictation/config.toml",
        "/home/me/Library/Application Support/Dictation/config.toml",
    ], "search order")
    expectEqual(
        ShortcutConfig.userConfigPath(environment: [:], home: "/home/me").path,
        "/home/me/.config/dictation/config.toml", "default user path")
}

func testShortcutConfigTemplate() {
    let template = ShortcutConfig.template
    let parsed = ShortcutConfig.parse(toml: template)
    expect(parsed.warnings.isEmpty, "template parses cleanly: \(parsed.warnings)")
    expectEqual(parsed.bindings, ShortcutConfig.defaults.bindings, "template leaves defaults in force")
    expect(template.contains("[shortcuts]"), "has the table header")
    for action in ShortcutAction.allCases {
        expect(template.contains("# \(action.rawValue)"), "documents \(action.rawValue)")
        expect(template.contains("\"\(action.defaultTrigger.configSpelling)\""), "shows \(action.rawValue)'s default")
    }
    // Uncommenting every binding must reproduce the defaults exactly.
    let uncommented = template
        .components(separatedBy: "\n")
        .map { line -> String in
            for action in ShortcutAction.allCases where line.hasPrefix("# \(action.rawValue) ") {
                return String(line.dropFirst(2))
            }
            return line
        }
        .joined(separator: "\n")
    let live = ShortcutConfig.parse(toml: uncommented)
    expect(live.warnings.isEmpty, "uncommented template parses cleanly: \(live.warnings)")
    expectEqual(live.bindings, ShortcutConfig.defaults.bindings, "uncommented template equals defaults")
}

func testShortcutConfigSeeding() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("dictation-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("nested/config.toml")

    expectEqual(ShortcutConfig.seedUserConfigIfMissing(searchPaths: [destination], destination: destination),
                destination, "writes the template when nothing exists")
    expectEqual(try? String(contentsOf: destination, encoding: .utf8), ShortcutConfig.template, "template contents")

    try! "[shortcuts]\nhold = \"f5\"\n".write(to: destination, atomically: true, encoding: .utf8)
    expect(ShortcutConfig.seedUserConfigIfMissing(searchPaths: [destination], destination: destination) == nil,
           "leaves an existing config alone")

    let elsewhere = directory.appendingPathComponent("elsewhere.toml")
    expect(ShortcutConfig.seedUserConfigIfMissing(searchPaths: [destination], destination: elsewhere) == nil,
           "an earlier search path suppresses seeding")
    expect(!FileManager.default.fileExists(atPath: elsewhere.path), "nothing written next to it")
}

func testShortcutConfigRebinding() {
    // The seeded template: the commented default line is replaced in place.
    let fromTemplate = ShortcutConfig.rebinding(.hold, to: Trigger(ctrlSpace), in: ShortcutConfig.template)
    let parsed = ShortcutConfig.parse(toml: fromTemplate)
    expectEqual(parsed[.hold], Trigger(ctrlSpace), "template rebinding takes effect")
    expectEqual(parsed[.toggle], Trigger(fn, taps: 2), "other bindings untouched")
    expect(parsed.warnings.isEmpty, "still parses cleanly: \(parsed.warnings)")
    expect(fromTemplate.contains("hold = \"ctrl+space\"  # hold to dictate, release to insert"), "line keeps its summary")
    let lines = fromTemplate.components(separatedBy: "\n")
    expect(!lines.contains { $0.hasPrefix("# hold ") }, "the commented line is gone")
    expect(lines.contains { $0.hasPrefix("# toggle ") }, "the other commented line stays")
    expectEqual(fromTemplate.components(separatedBy: "\n").count,
                ShortcutConfig.template.components(separatedBy: "\n").count, "no lines added or lost")

    // A live line is replaced too, and only once.
    let twice = ShortcutConfig.rebinding(.hold, to: Trigger(f5), in: fromTemplate)
    expectEqual(ShortcutConfig.parse(toml: twice)[.hold], Trigger(f5), "second rebinding replaces the first")
    expectEqual(twice.components(separatedBy: "\n").filter { $0.hasPrefix("hold") }.count, 1, "one hold line")

    // A [shortcuts] table with no line for the action gets one, before the
    // next table and its own blank-line padding.
    let sparse = "# my config\n[shortcuts]\nhold = \"f5\"\n\n[other]\nx = 1\n"
    let added = ShortcutConfig.rebinding(.toggle, to: Trigger(fn, taps: 2), in: sparse)
    expectEqual(added, "# my config\n[shortcuts]\nhold = \"f5\"\ntoggle = \"fn fn\"  # dictate hands-free; press once more to stop\n\n[other]\nx = 1\n",
                "inserted at the end of the table")

    // No table at all: one is appended.
    let empty = ShortcutConfig.rebinding(.hold, to: Trigger(fn), in: "")
    expectEqual(empty, "[shortcuts]\nhold = \"fn\"  # hold to dictate, release to insert\n", "fresh table")
    let commentsOnly = ShortcutConfig.rebinding(.hold, to: Trigger(fn), in: "# nothing here")
    expectEqual(commentsOnly, "# nothing here\n\n[shortcuts]\nhold = \"fn\"  # hold to dictate, release to insert\n",
                "appended after existing text")

    // A prose comment mentioning the key isn't mistaken for the binding.
    let prose = "[shortcuts]\n# note: hold = whatever you like\n# hold = \"fn\"\n"
    let fixed = ShortcutConfig.rebinding(.hold, to: Trigger(f5), in: prose)
    expect(fixed.contains("# note: hold = whatever you like"), "prose kept")
    expectEqual(ShortcutConfig.parse(toml: fixed)[.hold], Trigger(f5), "binding line replaced")

    // Writing to disk goes through the same path.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("dictation-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("config.toml")
    let written = try! ShortcutConfig.rebind(.toggle, to: Trigger(f5, taps: 2), at: file)
    expectEqual(written, file, "reports the file")
    let onDisk = ShortcutConfig.load(searchPaths: [file])
    expectEqual(onDisk[.toggle], Trigger(f5, taps: 2), "missing file is seeded from the template, then rebound")
    expectEqual(onDisk[.hold], Trigger(fn), "with the other default intact")
    expect(try! String(contentsOf: file, encoding: .utf8).hasPrefix("# Dictation shortcuts."), "documentation came along")
}

func testAppearanceConfig() {
    expectEqual(ShortcutConfig.defaults.appearance, .system, "default follows the system")
    expectEqual(ShortcutConfig.parse(toml: "[appearance]\ntheme = \"dark\"\n").appearance, .dark, "dark")
    expectEqual(ShortcutConfig.parse(toml: "[appearance]\ntheme = \"Light\"\n").appearance, .light, "case-insensitive")
    expect(ShortcutConfig.parse(toml: "[appearance]\ntheme = \"dark\"\n").warnings.isEmpty, "clean")

    let bad = ShortcutConfig.parse(toml: "[appearance]\ntheme = \"blue\"\nfont = \"x\"\n")
    expectEqual(bad.appearance, .system, "unknown value keeps the default")
    expect(bad.warnings.contains { $0.contains("theme = \"blue\"") && $0.contains("system, light, dark") },
           "explains the choices: \(bad.warnings)")
    expect(bad.warnings.contains { $0.contains("unknown appearance setting 'font'") }, "unknown key")
    expect(!bad.warnings.contains { $0.contains("[appearance]") }, "the table itself is known")

    // The template documents it, commented out; uncommenting equals the default.
    let template = ShortcutConfig.template
    expect(template.contains("[appearance]"), "template has the table")
    expect(template.contains("# theme = \"system\""), "template shows the default")
    expectEqual(ShortcutConfig.parse(toml: template.replacingOccurrences(of: "# theme =", with: "theme =")).appearance,
                .system, "uncommented template is the default")

    // Setting it edits in place, like rebinding.
    let fromTemplate = ShortcutConfig.settingAppearance(.dark, in: template)
    expectEqual(ShortcutConfig.parse(toml: fromTemplate).appearance, .dark, "template edit takes effect")
    expectEqual(ShortcutConfig.parse(toml: fromTemplate).bindings, ShortcutConfig.defaults.bindings, "shortcuts untouched")
    expectEqual(fromTemplate.components(separatedBy: "\n").count, template.components(separatedBy: "\n").count,
                "no lines added or lost")
    expect(fromTemplate.contains("theme = \"dark\"  # system, light, dark"), "line keeps the choices")

    let sparse = "[shortcuts]\nhold = \"f5\"\n"
    expectEqual(ShortcutConfig.settingAppearance(.light, in: sparse),
                "[shortcuts]\nhold = \"f5\"\n\n[appearance]\ntheme = \"light\"  # system, light, dark\n",
                "a missing table is appended")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("dictation-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("config.toml")
    try! ShortcutConfig.setAppearance(.dark, at: file)
    try! ShortcutConfig.rebind(.hold, to: Trigger(f5), at: file)
    let onDisk = ShortcutConfig.load(searchPaths: [file])
    expectEqual(onDisk.appearance, .dark, "theme survives a later shortcut rebind")
    expectEqual(onDisk[.hold], Trigger(f5), "and the rebind took")
}

// MARK: - Interaction model

func defaultModel() -> DictationInteractionModel {
    DictationInteractionModel(config: ShortcutConfig.defaults)
}

func testHoldToDictate() {
    var model = defaultModel()
    expectEqual(model.press(fn, at: 0), [.start(.hold)], "press starts a hold")
    expectEqual(model.mode, .hold, "listening in hold mode")
    expectEqual(model.release(fn, at: 2.0), [.finish], "a real hold finishes on release")
    expectEqual(model.mode, nil, "idle again")

    // A tap is not a hold: nothing was said, so nothing is inserted.
    expectEqual(model.press(fn, at: 5), [.start(.hold)], "tap still starts listening")
    expectEqual(model.release(fn, at: 5.1), [.cancel], "short release cancels")
    expectEqual(model.mode, nil, "idle after tap")

    // A later single press is just another hold, not a double tap.
    expectEqual(model.press(fn, at: 6), [.start(.hold)], "outside the window it's a hold again")
    expectEqual(model.release(fn, at: 6.05), [.cancel], "and a short one still cancels")
}

func testDoubleTapLocksHandsFree() {
    var model = defaultModel()
    expectEqual(model.press(fn, at: 0), [.start(.hold)], "first tap")
    expectEqual(model.release(fn, at: 0.1), [.cancel], "first tap released")
    expectEqual(model.press(fn, at: 0.3), [.start(.handsFree)], "second tap locks hands-free")
    expectEqual(model.mode, .handsFree, "hands-free")
    expectEqual(model.release(fn, at: 0.4), [], "releasing the second tap changes nothing")
    expectEqual(model.mode, .handsFree, "still listening")

    expectEqual(model.press(fn, at: 9), [.finish], "next press finishes")
    expectEqual(model.mode, nil, "idle")
    expectEqual(model.release(fn, at: 9.05), [], "its release is inert")

    // Stopping with a quick press-release-press must not restart: the stop
    // press is not the first half of a double tap.
    expectEqual(model.press(fn, at: 9.2), [.start(.hold)], "a press right after stopping is a fresh hold")
    expectEqual(model.release(fn, at: 9.25), [.cancel], "and its tap cancels")
}

func testDoubleTapWindowAndThreshold() {
    var model = defaultModel()
    model.doubleTapWindow = 0.4
    model.tapThreshold = 0.3

    _ = model.press(fn, at: 0)
    expectEqual(model.release(fn, at: 0.29), [.cancel], "just under the threshold is a tap")
    expectEqual(model.press(fn, at: 0.69), [.start(.handsFree)], "second press within window of the release")

    var late = defaultModel()
    _ = late.press(fn, at: 0)
    _ = late.release(fn, at: 0.1)
    expectEqual(late.press(fn, at: 0.6), [.start(.hold)], "too late for a double tap")

    var long = defaultModel()
    _ = long.press(fn, at: 0)
    expectEqual(long.release(fn, at: 0.3), [.finish], "at the threshold it's a hold")
    expectEqual(long.press(fn, at: 0.4), [.start(.hold)], "a hold is never the first half of a double tap")
}

func testSinglePressToggleOnAnotherKey() {
    var model = DictationInteractionModel(hold: Trigger(fn), toggle: Trigger(ctrlSpace))
    expectEqual(model.press(ctrlSpace, at: 0), [.start(.handsFree)], "single-press toggle starts hands-free")
    expectEqual(model.release(ctrlSpace, at: 0.1), [], "release is inert")
    expectEqual(model.press(fn, at: 1), [.finish], "either shortcut stops hands-free")
    expectEqual(model.release(fn, at: 1.5), [], "stop press release is inert even when long")

    expectEqual(model.press(fn, at: 3), [.start(.hold)], "hold still works")
    expectEqual(model.press(ctrlSpace, at: 3.2), [], "another key during a hold is ignored")
    expectEqual(model.release(ctrlSpace, at: 3.3), [], "and so is its release")
    expectEqual(model.release(fn, at: 4), [.finish], "the hold finishes normally")
}

func testDoubleTapToggleOnAnotherKey() {
    var model = DictationInteractionModel(hold: Trigger(ctrlSpace), toggle: Trigger(f5, taps: 2))
    expectEqual(model.press(f5, at: 0), [], "first F5 does nothing by itself")
    expectEqual(model.release(f5, at: 0.1), [], "nor its release")
    expectEqual(model.press(f5, at: 0.3), [.start(.handsFree)], "second F5 locks hands-free")
    expectEqual(model.release(f5, at: 0.4), [], "release of the second tap is inert")
    expectEqual(model.press(ctrlSpace, at: 2), [.finish], "hold key stops hands-free")
    expectEqual(model.release(ctrlSpace, at: 3), [], "without finishing twice")
}

func testStrayAndMissedEvents() {
    var model = defaultModel()
    expectEqual(model.release(fn, at: 0), [], "release with no press is ignored")
    expectEqual(model.press(ctrlSpace, at: 1), [], "unbound shortcut does nothing")
    expectEqual(model.release(ctrlSpace, at: 1.1), [], "…nor its release")

    // A missed release: the same key pressed again while believed down.
    expectEqual(model.press(fn, at: 2), [.start(.hold)], "hold starts")
    expectEqual(model.press(fn, at: 5), [.finish, .start(.hold)], "settles the old press, then starts anew")
    expectEqual(model.release(fn, at: 6), [.finish], "and the new hold finishes")

    model.reset()
    expectEqual(model.mode, nil, "reset clears mode")
    expectEqual(model.release(fn, at: 7), [], "reset clears the press")
}

func testSameSinglePressForBoth() {
    var model = DictationInteractionModel(hold: Trigger(ctrlSpace), toggle: Trigger(ctrlSpace))
    expectEqual(model.press(ctrlSpace, at: 0), [.start(.handsFree)], "the toggle wins")
    expectEqual(model.release(ctrlSpace, at: 2), [], "so there is no hold")
    expectEqual(model.press(ctrlSpace, at: 3), [.finish], "and a press stops")
}

// MARK: - Runner

@main
struct TestRunner {
    static func main() {
        testTOMLParsing()
        testShortcutParsing()
        testShortcutBindability()
        testTriggerParsing()
        testShortcutConfigOverrides()
        testShortcutConfigRejectsBadEntries()
        testShortcutConfigLoading()
        testShortcutConfigTemplate()
        testShortcutConfigSeeding()
        testShortcutConfigRebinding()
        testAppearanceConfig()
        testHoldToDictate()
        testDoubleTapLocksHandsFree()
        testDoubleTapWindowAndThreshold()
        testSinglePressToggleOnAnotherKey()
        testDoubleTapToggleOnAnotherKey()
        testStrayAndMissedEvents()
        testSameSinglePressForBoth()

        if failureCount > 0 {
            print("\(failureCount)/\(testCount) checks FAILED")
            exit(1)
        }
        print("All \(testCount) checks passed")
    }
}
