import AppKit
import Testing
@testable import CodexBar

struct MenuBarUsageTintTests {
    private func components(_ color: NSColor) throws -> (red: Double, green: Double, blue: Double) {
        let srgb = try #require(color.usingColorSpace(.sRGB))
        return (srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
    }

    @Test
    func `unknown usage yields no tint`() {
        #expect(MenuBarUsageTint.color(forUsedPercent: nil) == nil)
    }

    @Test
    func `tint shifts from green toward red as usage rises`() throws {
        let samples = [0.0, 20, 40, 60, 70, 80, 90, 100]
        let ramp = try samples.map { try self.components(#require(MenuBarUsageTint.color(forUsedPercent: $0))) }

        for (lower, higher) in zip(ramp, ramp.dropFirst()) {
            #expect(higher.red >= lower.red)
            #expect(higher.green <= lower.green)
        }
        let lowest = try #require(ramp.first)
        let highest = try #require(ramp.last)
        #expect(highest.red > lowest.red)
        #expect(highest.green < lowest.green)
    }

    @Test(arguments: [90.0, 95, 100, 250])
    func `usage at or past the critical threshold clamps to one color`(usedPercent: Double) throws {
        let critical = try self.components(#require(MenuBarUsageTint.color(forUsedPercent: 90)))
        let sampled = try self.components(#require(MenuBarUsageTint.color(forUsedPercent: usedPercent)))

        #expect(sampled == critical)
    }

    @Test
    func `negative usage clamps to the low end`() throws {
        let floorColor = try self.components(#require(MenuBarUsageTint.color(forUsedPercent: 0)))
        let belowFloor = try self.components(#require(MenuBarUsageTint.color(forUsedPercent: -25)))

        #expect(belowFloor == floorColor)
    }

    /// Tints are baked into non-template bitmaps, so they must not be dynamic colors: a dynamic color would be
    /// resolved at render time and go stale when the system appearance changes. This is what lets the renderer
    /// skip an `effectiveAppearance` observer.
    @Test(arguments: [0.0, 50, 95])
    func `tints resolve identically regardless of appearance`(usedPercent: Double) throws {
        let color = try #require(MenuBarUsageTint.color(forUsedPercent: usedPercent))
        var light: (red: Double, green: Double, blue: Double)?
        var dark: (red: Double, green: Double, blue: Double)?

        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            light = try? self.components(color)
        }
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            dark = try? self.components(color)
        }

        #expect(light != nil)
        #expect(light == dark)
    }
}
