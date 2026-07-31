import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct IconRendererUsageTintTests {
    private func pixels(_ image: NSImage) throws -> Data {
        try #require(image.tiffRepresentation)
    }

    private func icon(tint: NSColor?, hideCritters: Bool = false) -> NSImage {
        IconRenderer.makeIcon(
            primaryRemaining: 60,
            weeklyRemaining: 40,
            creditsRemaining: nil,
            stale: false,
            style: .codex,
            hideCritters: hideCritters,
            tint: tint)
    }

    @Test
    func `untinted icons stay template images`() {
        #expect(self.icon(tint: nil).isTemplate)
    }

    /// A template image keeps only its alpha mask, so AppKit recolors it and the RGB never reaches the menu bar.
    /// Baking the tint into a non-template bitmap is what makes color survive on macOS 26.
    @Test
    func `tinted icons are baked as non template images`() {
        #expect(self.icon(tint: .systemRed).isTemplate == false)
    }

    @Test
    func `omitting the tint reproduces the untinted render exactly`() throws {
        let explicitNil = self.icon(tint: nil)
        let omitted = IconRenderer.makeIcon(
            primaryRemaining: 60,
            weeklyRemaining: 40,
            creditsRemaining: nil,
            stale: false,
            style: .codex)

        #expect(try self.pixels(explicitNil) == self.pixels(omitted))
    }

    @Test
    func `a tint changes the rendered pixels`() throws {
        #expect(try self.pixels(self.icon(tint: nil)) != self.pixels(self.icon(tint: .systemRed)))
    }

    /// Guards the icon cache key: two different tints must not collide on one entry.
    @Test
    func `distinct tints render distinctly`() throws {
        let low = try #require(MenuBarUsageTint.color(forUsedPercent: 10))
        let high = try #require(MenuBarUsageTint.color(forUsedPercent: 95))

        #expect(try self.pixels(self.icon(tint: low)) != self.pixels(self.icon(tint: high)))
    }

    @Test
    func `tint and hide critters stay independent`() throws {
        let tint = try #require(MenuBarUsageTint.color(forUsedPercent: 80))
        let decorated = self.icon(tint: tint, hideCritters: false)
        let plain = self.icon(tint: tint, hideCritters: true)

        #expect(try self.pixels(decorated) != self.pixels(plain))
        #expect(decorated.isTemplate == false)
        #expect(plain.isTemplate == false)
    }

    @Test
    func `morph icons ignore the tint and stay template`() {
        #expect(IconRenderer.makeMorphIcon(progress: 0.5, style: .codex).isTemplate)
    }
}
