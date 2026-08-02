import AppKit
import Foundation

/// Maps how much of a quota is used to a menu bar icon tint.
///
/// The colors are fixed sRGB rather than the dynamic `NSColor.system*` palette. A tinted icon is baked into a
/// non-template bitmap (see `IconRenderer.makeIcon(tint:)`), so any dynamic color would be frozen at render time
/// and go stale on a light/dark switch. Fixed components keep the render a pure function of its inputs, which is
/// also what lets the icon cache key hash the tint safely.
///
/// The values are mid-luminance and high-chroma so they stay legible against a light menu bar, a dark menu bar,
/// and a translucent one over an arbitrary wallpaper. `NSColor.systemGreen` in particular is far too light on
/// white. Color is never the only signal: the bar fill length already encodes the same value.
/// Which part of a menu bar layout strip `MenuBarUsageTint` colors.
///
/// The meter icon is a single glyph, so the legacy render path has nothing to choose between. A layout strip is a
/// row of independent tokens, and which of them should carry the color is a taste call rather than a correct one.
enum MenuBarUsageColorTarget: String, CaseIterable, Identifiable, Sendable {
    /// Each case adds to the one above it — the provider logo always carries the tint, because a colored
    /// number beside an uncolored logo reads as a rendering bug rather than as a deliberate scope.
    ///
    /// Only the provider logo.
    case icon
    /// The logo plus percent, pace, usage bar, and run-out tokens — the ones whose value the color restates.
    case usage
    /// The whole strip, including account and cost tokens.
    case everything

    var id: String {
        self.rawValue
    }

    var label: String {
        switch self {
        case .icon: L("menu_bar_usage_colors_target_icon")
        case .usage: L("menu_bar_usage_colors_target_usage")
        case .everything: L("menu_bar_usage_colors_target_everything")
        }
    }
}

enum MenuBarUsageTint {
    /// Comfortably inside the quota.
    private static let low = NSColor(srgbRed: 0.14, green: 0.60, blue: 0.25, alpha: 1)
    /// Approaching the limit.
    private static let medium = NSColor(srgbRed: 0.85, green: 0.48, blue: 0.02, alpha: 1)
    /// At or past the point where the window is likely to run out.
    private static let high = NSColor(srgbRed: 0.80, green: 0.13, blue: 0.13, alpha: 1)

    private static let mediumThreshold: Double = 70
    private static let highThreshold: Double = 90

    /// - Parameter usedPercent: Percentage of the window consumed, or `nil` when usage is unknown.
    /// - Returns: The tint to draw the icon in, or `nil` to leave the icon as an untinted template.
    static func color(forUsedPercent usedPercent: Double?) -> NSColor? {
        guard let usedPercent else { return nil }
        let clamped = min(max(usedPercent, 0), 100)

        if clamped < Self.mediumThreshold {
            let fraction = clamped / Self.mediumThreshold
            return Self.low.blended(withFraction: fraction, of: Self.medium) ?? Self.low
        }
        if clamped < Self.highThreshold {
            let fraction = (clamped - Self.mediumThreshold) / (Self.highThreshold - Self.mediumThreshold)
            return Self.medium.blended(withFraction: fraction, of: Self.high) ?? Self.medium
        }
        return Self.high
    }
}
