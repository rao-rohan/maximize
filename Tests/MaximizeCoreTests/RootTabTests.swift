import XCTest
@testable import MaximizeCore

/// `RootTab` has no logic either — like `ScoreBand`, what is worth pinning is the
/// *claim*. The tab bar is the app's statement about what its parallel modes are, and
/// the failure mode this suite exists to catch is a later ticket adding a fourth tab or
/// reordering the three because a `Tab` is cheap to type. Each of these assertions
/// should be annoying to change, because each of them was argued for once.
final class RootTabTests: XCTestCase {

    /// Order is the tab bar's left-to-right order, and the first case is what the app
    /// opens to. See `RootTab`'s documentation for why Workouts leads and Plan is last.
    func testTabsAreExactlyTheThreeModesInOrder() {
        XCTAssertEqual(RootTab.allCases, [.workouts, .dashboard, .plan])
    }

    /// MAX-081 removed Settings from the tab bar deliberately: it is a destination you
    /// leave, not a mode you inhabit. Stated as its own test so that putting it back
    /// fails with the reason attached rather than as an off-by-one on a count.
    func testSettingsIsNotATab() {
        XCTAssertFalse(
            RootTab.allCases.map(\.rawValue).contains("settings"),
            "Settings reaches all three tabs as a toolbar button (MAX-081) and does not get a slot."
        )
        XCTAssertFalse(RootTab.allCases.map(\.title).contains("Settings"))
    }

    func testEveryTabHasADistinctLabel() {
        let titles = RootTab.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "Two tabs share a label: \(titles)")
        XCTAssertFalse(titles.contains(where: \.isEmpty))
    }

    /// A tab item is a glyph *and* a label, and at a glance it is read as the glyph. Two
    /// tabs sharing a symbol would leave the label doing all the work, at tab-item size.
    func testEveryTabHasADistinctSymbol() {
        let symbols = RootTab.allCases.map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, symbols.count, "Two tabs share a symbol: \(symbols)")
        XCTAssertFalse(symbols.contains(where: \.isEmpty))
    }

    /// The symbols are strings the app layer hands to SF Symbols, and a typo there
    /// renders as a blank tab item rather than as a build failure — nothing in CI draws
    /// a glyph. This is the cheap half of the check: the names are well-formed. The
    /// other half is a device check, listed in the PR.
    func testSymbolNamesAreWellFormed() {
        for tab in RootTab.allCases {
            let name = tab.symbolName
            XCTAssertEqual(name, name.lowercased(), "SF Symbol names are lowercase: \(name)")
            XCTAssertFalse(name.hasPrefix("."), "Leading dot in \(name)")
            XCTAssertFalse(name.hasSuffix("."), "Trailing dot in \(name)")
            XCTAssertFalse(name.contains(where: \.isWhitespace), "Whitespace in \(name)")
        }
    }

    /// Raw values are not persisted today, but a tab identifier is the natural key for a
    /// restored-selection preference, and MAX-098's accessory will want to name a tab.
    /// Pinning them now costs nothing and keeps that option open.
    func testRawValuesAreStable() {
        XCTAssertEqual(RootTab.allCases.map(\.rawValue), ["workouts", "dashboard", "plan"])
    }
}
