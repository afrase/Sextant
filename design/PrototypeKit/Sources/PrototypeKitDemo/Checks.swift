import AppKit
import PrototypeKit

/// Self-checks for PrototypeKit. Prints a report; returns the number of failures.
@MainActor
func runChecks() -> Int {
    var failures = 0
    func check(_ ok: Bool, _ what: String) {
        if ok { print("  ok   \(what)") } else { print("  FAIL \(what)"); failures += 1 }
    }

    print("== Layout")
    let layout = Samples.layout
    check(layout.title == "My MacOS Layout [fork]", "title \(layout.title)")
    check(layout.layers.map(\.title) == ["Main", "Sym+Num", "Brd+Sys"], "layers \(layout.layerNames)")
    check(layout.layers[1].color?.hex == "#00F0FF" && layout.layers[2].color?.hex == "#42FF00", "layer colours")
    check(layout.layers.allSatisfy { $0.keys.count == 52 }, "52 keys per layer")
    check(layout.firmwareVersion == "25.0" && layout.id == "KlgM7" && layout.revisionId == "40xJ7M", "identity KlgM7/40xJ7M fw 25.0")

    print("== Kinds (Main)")
    let k = layout.layers[0].keys
    let expected: [Int: KeyKind] = [0: .multiFunction, 1: .regular, 12: .modifier, 18: .modifier, 19: .multiFunction, 24: .multiFunction,
                                    25: .modifier, 43: .multiFunction, 48: .multiFunction, 49: .modifier, 50: .regular, 51: .multiFunction]
    for (i, kind) in expected.sorted(by: { $0.key < $1.key }) { check(k[i].kind == kind, "key \(i) is \(kind) (got \(k[i].kind))") }
    let l2 = layout.layers[2].keys
    check(l2[0].kind == .ledControl && l2[21].kind == .ledControl && l2[1].kind == .ledControl, "Brd+Sys RGB keys are LED control")
    check(l2[44].kind == .customLabel && l2[31].kind == .regular && l2[18].kind == .transparent && l2[26].kind == .transparent, "Brd+Sys custom/QK_BOOT/transparent")
    for (li, l) in layout.layers.enumerated() {
        let counts = Dictionary(grouping: l.keys, by: \.kind).mapValues(\.count).sorted { $0.key.rawValue < $1.key.rawValue }
        print("     layer \(li): " + counts.map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", "))
    }

    print("== Legends")
    func show(_ l: Int, _ i: Int) -> String {
        let r = Legends.legend(layout: layout, layer: l, index: i)
        let p = r.legend.primary.map { $0.text + ($0.side.map { "(\($0.rawValue.prefix(1).uppercased()))" } ?? "") } ?? "·"
        let s = r.legend.secondary.map { " / " + $0.text + ($0.side.map { "(\($0.rawValue.prefix(1).uppercased()))" } ?? "") } ?? ""
        return "\(p)\(s)\(r.isInherited ? " [inherited]" : "")"
    }
    let main = (0..<52).map { show(0, $0) }
    print("     Main: " + main.joined(separator: " | "))
    check(show(0, 0) == "= / ⎋", "key 0 = / ⎋ (\(show(0, 0)))")
    check(show(0, 19) == "Z / ⌥(L)", "key 19 Z / ⌥L (\(show(0, 19)))")
    check(show(0, 43) == "' / ⇧(R)", "key 43 ' / ⇧R (\(show(0, 43)))")
    check(show(0, 24) == "⏎ / Sym+Num", "key 24 ⏎ / Sym+Num (\(show(0, 24)))")
    check(show(0, 51) == "␣ / Brd+Sys", "key 51 ␣ / Brd+Sys (\(show(0, 51)))")
    check(show(0, 18) == "⌃(L)" && show(0, 25) == "⌘(L)" && show(0, 49) == "⌃(R)", "hold-only and right modifiers")
    check(show(2, 26) == "6 [inherited]", "Brd+Sys key 26 inherits 6 from Main, not F6 (\(show(2, 26)))")
    check(show(2, 18) == "⌃(L) [inherited]", "empty Brd+Sys key 18 inherits Left Control (\(show(2, 18)))")
    check(show(2, 44) == "Back", "custom label Back (\(show(2, 44)))")
    check(Legends.legend(for: layout.layers[2].keys[45]).annotation == "⇧⌘[", "Prev Tab annotation ⇧⌘[")
    check(show(2, 31) == "Reset", "QK_BOOT legend Reset")
    check(Legends.legend(for: layout.layers[0].keys[24]).qmk == "LT(1, KC_ENTER)", "QMK LT(1, KC_ENTER)")
    check(Legends.legend(for: layout.layers[0].keys[19]).qmk == "MT(MOD_LALT, KC_Z)", "QMK MT(MOD_LALT, KC_Z)")
    check(Legends.legend(layout: layout, layer: 2, index: 51).activatesDisplayedLayer, "key 51 marked as holding Brd+Sys")
    print("     Brd+Sys: " + (0..<52).map { show(2, $0) }.joined(separator: " | "))

    print("== Catalog")
    let entries = KeycodeCatalog.entries
    check(entries.count >= 250, "\(entries.count) entries")
    check(Set(entries.map(\.code)).count == entries.count, "unique codes")
    print("     " + KeycodeCategory.allCases.map { "\($0.title) \(KeycodeCatalog.entries(in: $0).count)" }.joined(separator: ", "))
    var userCodes = Set<String>()
    for l in layout.layers { for key in l.keys { for (_, a) in key.actions { userCodes.insert(a.code) } } }
    let missing = userCodes.filter { KeycodeCatalog.entry(for: $0) == nil && !KeycodeCatalog.layerFunctions.contains($0) }
    check(missing.isEmpty, "every code in the user's layout is catalogued (\(userCodes.count) codes) \(missing.sorted())")
    // Wider coverage: the public example layouts in the research folder (read-only).
    let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "docs/research/oryx-examples")
    var exampleCodes = Set<String>()
    for f in (try? FileManager.default.contentsOfDirectory(at: examples, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "json" {
        guard let l = try? KeyboardLayout(oryxFile: f) else { print("     (could not decode \(f.lastPathComponent))"); continue }
        for layer in l.layers { for key in layer.keys { for (_, a) in key.actions { exampleCodes.insert(a.code); a.macro?.steps.forEach { exampleCodes.insert($0.code) } } } }
    }
    let exMissing = exampleCodes.filter { KeycodeCatalog.entry(for: $0) == nil && !KeycodeCatalog.layerFunctions.contains($0) }.sorted()
    print("     example layouts: \(exampleCodes.count) codes, not catalogued: \(exMissing)")
    var badSymbols: [String] = []
    let symbols = entries.compactMap(\.symbol) + KeyKind.allCases.map(\.symbolName) + KeySlot.allCases.map(\.symbolName) + KeycodeCategory.allCases.map(\.symbolName)
    for s in Set(symbols) where NSImage(systemSymbolName: s, accessibilityDescription: nil) == nil { badSymbols.append(s) }
    check(badSymbols.isEmpty, "all \(Set(symbols).count) SF Symbol names exist \(badSymbols.sorted())")
    for q in ["esc", "vol", "cmd", "⌘", "pgdn", "bright", "layer", "boot", "lbrc", "[", "scroll", "copy", "dbl", "f12", "kana"] {
        print("     search \"\(q)\": " + KeycodeCatalog.search(q, limit: 5).map { "\($0.label)(\($0.code))" }.joined(separator: " "))
    }
    check(KeycodeCatalog.search("esc").first?.code == "KC_ESCAPE", "search esc → Escape first")
    check(KeycodeCatalog.search("⌘").first?.code == "KC_LEFT_GUI", "search ⌘ → Left Command first")
    check(KeycodeCatalog.search("pgdn").first?.code == "KC_PGDN", "search pgdn → Page Down first")
    check(KeycodeCatalog.canonicalCode("KC_LSFT") == "KC_LEFT_SHIFT" && KeycodeCatalog.canonicalCode("RGB_MOD") == "RGB_MODE_FORWARD", "aliases")

    print("== Geometry")
    let geo = BoardGeometry.voyager
    let pts = geo.layout(keySize: 60, spacing: 6)
    var overlaps: [String] = []
    for a in pts.frames { for b in pts.frames where a.index < b.index && polygonsOverlap(a.corners, b.corners) { overlaps.append("\(a.index)-\(b.index)") } }
    check(overlaps.isEmpty, "no overlapping caps \(overlaps)")
    check(abs(geo.key(3).center.y - geo.key(0).center.y + 0.30) < 0.001 && abs(geo.key(2).center.y - geo.key(0).center.y + 0.15) < 0.001, "left column stagger 0.15 / 0.30")
    check(abs(geo.key(28).center.y - geo.key(3).center.y) < 0.001 && abs(geo.key(27).center.y - geo.key(4).center.y) < 0.001, "right half mirrors stagger")
    check(geo.key(24).rotation == 30 && geo.key(25).rotation == 30 && geo.key(50).rotation == -30 && geo.key(51).rotation == -30, "thumb rotation ±30°")
    check(geo.key(25).size.height > geo.key(24).size.height, "inner thumbs are taller")
    check(abs((geo.key(24).center.x + geo.key(51).center.x) / 2 - (geo.key(0).center.x + geo.key(31).center.x) / 2) < 0.001, "thumbs mirror about the centre")
    print("     bounds \(geo.bounds) left \(geo.bounds(of: .left)) right \(geo.bounds(of: .right)); points \(pts.size)")
    for i in [0, 3, 5, 23, 24, 25, 26, 50, 51] { print("     key \(i) centre \(geo.key(i).center) size \(geo.key(i).size) rot \(geo.key(i).rotation)") }
    check(geo.neighbor(of: 5, toward: .right) == 26 && geo.neighbor(of: 23, toward: .down) == 24 && geo.neighbor(of: 16, toward: .up) == 10, "arrow navigation 5→26, 23↓24, 16↑10")
    check(pts.keyIndex(at: pts.frame(25).center) == 25, "hit test rotated thumb")

    print("== Editor")
    let store = EditorStore()
    store.select(key: 13)
    store.setTap("KC_Q")
    check(store.layout.key(layer: 0, index: 13)?.tap?.code == "KC_Q" && store.undoActionName == "Set Tap", "set tap")
    store.setHold("KC_LEFT_CTRL")
    check(store.layout.key(layer: 0, index: 13)?.kind == .multiFunction, "set hold → tap+hold")
    store.setLabel("Ctrl A")
    store.setColor(HexColor(hex: "#FF8800"))
    let added = store.addLayer(title: "Gaming", color: HexColor(hex: "#FF00AA"))
    store.renameLayer(added, to: "Games")
    store.moveLayer(from: 1, to: 3)
    check(store.layout.layerNames == ["Main", "Brd+Sys", "Games", "Sym+Num"], "move layer \(store.layout.layerNames)")
    check(store.layout.key(layer: 0, index: 24)?.hold?.layer == 3 && store.layout.key(layer: 0, index: 51)?.hold?.layer == 1, "layer references follow the move")
    for _ in 0..<6 { store.undo() }
    check(store.layout == Samples.layout, "six undos restore the original")
    store.redo()
    check(store.layout.key(layer: 0, index: 13)?.tap?.code == "KC_Q", "redo")
    store.select(key: 5)
    store.moveSelection(.right)
    check(store.selection.keyIndex == 26, "selection crosses halves")

    print("== Samples")
    let h = Samples.history
    let diffs = h.revisions.indices.map { h.diffToPrevious($0).keyChanges.count }
    check(h.revisions.count == 4 && diffs == [0, 2, 4, 4], "history diffs \(diffs)")
    check(Samples.heatmap.total() > 100_000 && Samples.heatmap.top(1, layer: 0).first?.index == 51, "heatmap total \(Samples.heatmap.total()), top key \(Samples.heatmap.top(3, layer: 0))")
    let dev = MockDevice.frozen(at: 2.6)
    check(dev.activeLayer == 2 && dev.pressedKeys == [51, 40], "device at 2.6 s: layer \(dev.activeLayer), pressed \(dev.pressedKeys.sorted())")
    check(MockDevice.frozen(at: 4.6).activeLayer == 1, "device at 4.6 s holds Sym+Num")
    let ref = OryxLayoutReference("https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0")
    check(ref?.layoutID == "KlgM7" && ref?.revisionID == "40xJ7M" && ref?.layer == 0, "parse Oryx URL")
    check(OryxLayoutReference("KlgM7/40xJ7M")?.revisionID == "40xJ7M" && OryxLayoutReference("KlgM7")?.revisionID == nil, "parse serial and bare id")
    check(Samples.oryxImport.summary.customLabels == 4 && Samples.oryxImport.summary.colorKeys == 3, "import summary \(Samples.oryxImport.summary)")
    check(SettingsCatalog.voyager.sections.count == 14 && SettingsCatalog.voyager.allSettings.count == 100, "settings 14 / 100")
    check(SettingsCatalog.voyager.setting(id: "tappingTerm")?.defaultValue == .number(200), "tapping term default 200")
    check(SettingsCatalog.voyager.search("chordal").count == 2, "settings search chordal")
    check(SettingsCatalog.voyager.modified(in: Samples.settingsOverrides).count == Samples.settingsOverrides.count, "sample overrides all differ from defaults")
    check(Samples.appRuleActiveLayer == 1, "Xcode rule → Sym+Num")
    let sim = BuildFlashSimulator.at(.failedUnknownKeycode)
    if case let .failed(f) = sim.phase { check(f.key == KeyRef(layer: 2, index: 45), "build error mapped to Brd+Sys key 45") } else { check(false, "build failure state") }
    check(BuildFlashSimulator.at(.done).phase.overallProgress == 1, "flash done")

    print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
    return failures
}

/// Separating-axis test for two convex quads.
func polygonsOverlap(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
    for poly in [a, b] {
        for i in 0..<poly.count {
            let p1 = poly[i], p2 = poly[(i + 1) % poly.count]
            let axis = CGPoint(x: p2.y - p1.y, y: p1.x - p2.x)
            let pa = a.map { $0.x * axis.x + $0.y * axis.y }, pb = b.map { $0.x * axis.x + $0.y * axis.y }
            if pa.max()! <= pb.min()! + 0.01 || pb.max()! <= pa.min()! + 0.01 { return false }
        }
    }
    return true
}
