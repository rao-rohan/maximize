import SwiftUI

// MARK: - The split
//
// PRD §7.4 resolves the Liquid Glass / Robinhood tension by assigning them to
// different layers rather than blending them:
//
//   chrome  — tab bar, nav bars, toolbars, sheets, floating controls → Liquid Glass
//   content — charts, calendar, tiles, lists                        → flat and opaque
//
// FR-4.2 is the load-bearing half. Refraction and blur destroy fine chart lines and
// the HR cap threshold, which is the entire reason those views exist. So this file is
// written to make the correct path the short one:
//
//   * `contentSurface()` takes no arguments and is opaque by construction. It is the
//     shortest thing to type, and there is no parameter that can make it translucent.
//   * `glassChrome(_:)` cannot be called without naming a `ChromeRole`. Applying it to
//     a chart means writing `.glassChrome(.floatingControl)` on a chart — a sentence
//     that is visibly wrong in review and trivially greppable.
//   * A content surface marks its subtree in the environment. Glass inside that
//     subtree trips an assertion in debug builds and **silently degrades to the opaque
//     fallback in release**, so the mistake cannot reach a user's screen even if it
//     reaches main.
//
// The last point is the difference between a convention and a constraint.

// MARK: - Content surfaces

/// A flat, opaque place for data to sit.
///
/// The cases differ only in fill, radius and padding. None of them has a translucent
/// variant, and none can be given one without editing this file.
enum ContentSurface {
    /// The screen background behind everything. Extends under the chrome so Liquid
    /// Glass has something to refract.
    case screen

    /// A chart container or a grouped card.
    case card

    /// A summary tile or a calendar cell.
    case tile

    /// A well inside a card: a plot area, a segmented-control track.
    case inset

    fileprivate var fill: Color {
        switch self {
        case .screen: return .surface
        case .card, .tile: return .surfaceElevated
        case .inset: return .surfaceInset
        }
    }

    fileprivate var cornerRadius: CGFloat {
        switch self {
        case .screen: return 0
        case .card: return CornerRadius.card
        case .tile: return CornerRadius.tile
        case .inset: return CornerRadius.control
        }
    }

    fileprivate var padding: CGFloat {
        switch self {
        case .screen: return 0
        case .card: return Layout.surfacePadding
        case .tile: return Spacing.compact
        case .inset: return Spacing.snug
        }
    }
}

extension View {

    /// Places this view on a flat, opaque content surface — the default treatment for
    /// anything that renders data (FR-4.2).
    ///
    /// Reach for this first. It is deliberately the zero-argument call: charts, the
    /// calendar, summary tiles and lists all want `.contentSurface()` and nothing else.
    ///
    /// Beyond drawing the surface, this marks the subtree as content, which is what
    /// stops `glassChrome(_:)` from taking effect inside it.
    func contentSurface(_ surface: ContentSurface = .card) -> some View {
        modifier(ContentSurfaceModifier(surface: surface))
    }

    /// Standard horizontal inset from the screen edge (`Layout.screenMargin`).
    ///
    /// Separate from `contentSurface(.screen)` because a scrolling screen usually
    /// wants its background edge-to-edge and its content inset.
    func screenMargins() -> some View {
        padding(.horizontal, Layout.screenMargin)
    }
}

private struct ContentSurfaceModifier: ViewModifier {
    let surface: ContentSurface

    @ViewBuilder
    func body(content: Content) -> some View {
        switch surface {
        case .screen:
            // Deliberately does *not* mark the subtree as content. A screen background
            // is a backdrop, not a data container, and chrome legitimately floats over
            // a screen — flagging it here would make every correct use of
            // `glassChrome(_:)` trip the assertion. The flag belongs to the bounded
            // surfaces that actually hold data.
            content
                .background { surface.fill.ignoresSafeArea() }
        case .card, .tile, .inset:
            let shape = RoundedRectangle(cornerRadius: surface.cornerRadius, style: .continuous)
            content
                .padding(surface.padding)
                .background(surface.fill, in: shape)
                .clipShape(shape)
                .environment(\.isWithinContentSurface, true)
        }
    }
}

// MARK: - Chrome

/// The navigation-layer element Liquid Glass is being applied to.
///
/// This argument exists to be load-bearing at the call site. Every case names
/// something Apple's HIG classifies as chrome; there is no `.content`, no `.card`, no
/// `.chart`, and adding one would be the actual design regression.
///
/// Note that the tab bar and navigation bars already get Liquid Glass for free from
/// the iOS 26 SDK (FR-4.1). Those cases exist for custom bars that stand in for the
/// system ones, not to re-apply glass to the system's own.
enum ChromeRole {
    case navigationBar
    case toolbar
    case tabBar
    case sheet
    case floatingControl

    fileprivate var shape: AnyShape {
        switch self {
        case .floatingControl:
            return AnyShape(Capsule(style: .continuous))
        case .sheet:
            return AnyShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        case .navigationBar, .toolbar, .tabBar:
            return AnyShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        }
    }

    fileprivate var name: String {
        switch self {
        case .navigationBar: return "navigationBar"
        case .toolbar: return "toolbar"
        case .tabBar: return "tabBar"
        case .sheet: return "sheet"
        case .floatingControl: return "floatingControl"
        }
    }
}

extension View {

    /// Applies Liquid Glass to a piece of **chrome** (FR-4.1).
    ///
    /// Degrades to an opaque fill in two situations, both of which produce a solid,
    /// readable control rather than a missing one:
    ///
    /// - **Reduce Transparency is on** (FR-4.5). This is the whole of the a11y
    ///   requirement for chrome, handled once, here, rather than at each call site.
    /// - **The caller is inside a content surface** — i.e. glass is being applied over
    ///   data, which FR-4.2 forbids. Debug builds trap on it; release builds quietly
    ///   do the right thing.
    func glassChrome(_ role: ChromeRole) -> some View {
        modifier(GlassChromeModifier(role: role, shape: role.shape))
    }

    /// As `glassChrome(_:)`, with an explicit shape for chrome whose silhouette is not
    /// the role's default.
    func glassChrome(_ role: ChromeRole, in shape: some Shape) -> some View {
        modifier(GlassChromeModifier(role: role, shape: AnyShape(shape)))
    }
}

private struct GlassChromeModifier: ViewModifier {
    let role: ChromeRole
    let shape: AnyShape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isWithinContentSurface) private var isWithinContentSurface

    private var shouldUseGlass: Bool {
        !reduceTransparency && !isWithinContentSurface
    }

    func body(content: Content) -> some View {
        glassOrFallback(content)
            .onAppear(perform: reportMisuseIfNeeded)
    }

    @ViewBuilder
    private func glassOrFallback(_ content: Content) -> some View {
        if shouldUseGlass {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(Color.chromeOpaque, in: shape)
        }
    }

    /// Debug-only tripwire. `assertionFailure` compiles out of release builds, where
    /// `shouldUseGlass` has already made the outcome safe.
    private func reportMisuseIfNeeded() {
        guard isWithinContentSurface else { return }
        assertionFailure(
            """
            glassChrome(.\(role.name)) was applied inside a content surface. \
            PRD FR-4.2 forbids translucency over data — refraction destroys fine chart \
            lines and the HR cap threshold. Move this control out of the content \
            subtree, or give it .contentSurface() instead.
            """
        )
    }
}

// MARK: - Environment

private struct IsWithinContentSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True anywhere inside a bounded content surface — a card, tile or inset. Not set
    /// by `contentSurface(.screen)`, which is a backdrop rather than a data container.
    ///
    /// Set by the design system, read by the design system. Views should not need to
    /// consult it; if one does, that is a sign a component is trying to be both chrome
    /// and content, which is the ambiguity §7.4 exists to remove.
    var isWithinContentSurface: Bool {
        get { self[IsWithinContentSurfaceKey.self] }
        set { self[IsWithinContentSurfaceKey.self] = newValue }
    }
}
