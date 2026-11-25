import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// Fork-only: how the color-coded usage tint lands on a layout strip. Lives in its own file so an upstream sync
/// never has to merge these into upstream's renderer suite.
extension MenuBarLayoutRendererTests {
    @Test
    func `usage color target decides which tokens carry the tint`() throws {
        let renderer = MenuBarLayoutRenderer()
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        icon.isTemplate = true
        let layout = MenuBarLayout(lines: [[.icon, .accountLabel, .percent(window: .automatic)]])
        // `data()` reports 50% used, which is inside the tint ramp rather than at either clamp.
        let tint = try #require(MenuBarUsageTint.color(forUsedPercent: 50))

        func colors(target: MenuBarUsageColorTarget?) -> (account: NSColor?, percent: NSColor?) {
            let output = renderer.render(
                layout: layout,
                data: self.data(),
                icon: icon,
                options: self.options(usageColorTarget: target))
            let title = output.attributedTitle
            let accountIndex = (title.string as NSString).range(of: "user@example.com").location
            let percentIndex = (title.string as NSString).range(of: "50%").location
            return (
                title.attribute(.foregroundColor, at: accountIndex, effectiveRange: nil) as? NSColor,
                title.attribute(.foregroundColor, at: percentIndex, effectiveRange: nil) as? NSColor)
        }

        let off = colors(target: nil)
        #expect(off.account == .controlTextColor)
        #expect(off.percent == .controlTextColor)

        let usageOnly = colors(target: .usage)
        #expect(usageOnly.account == .controlTextColor)
        #expect(usageOnly.percent == tint)

        let everything = colors(target: .everything)
        #expect(everything.account == tint)
        #expect(everything.percent == tint)

        let iconOnly = colors(target: .icon)
        #expect(iconOnly.account == .controlTextColor)
        #expect(iconOnly.percent == .controlTextColor)
    }

    @Test
    func `tinted icon stops being a template so AppKit keeps the color`() throws {
        let renderer = MenuBarLayoutRenderer()
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        icon.isTemplate = true

        func attachmentImage(target: MenuBarUsageColorTarget?) throws -> NSImage? {
            let output = renderer.render(
                layout: MenuBarLayout(lines: [[.icon, .percent(window: .automatic)]]),
                data: self.data(),
                icon: icon,
                options: self.options(usageColorTarget: target))
            // An untinted leading icon is promoted to the status item image instead of an attachment.
            guard let attachment = output.attributedTitle.attribute(.attachment, at: 0, effectiveRange: nil)
                as? NSTextAttachment
            else { return output.leadingIcon }
            return attachment.image
        }

        #expect(try attachmentImage(target: nil)?.isTemplate == true)
        // Every target tints the icon, so none of them may leave it a template.
        for target in MenuBarUsageColorTarget.allCases {
            #expect(try attachmentImage(target: target)?.isTemplate == false)
        }
    }

    @Test
    func `usage tint outranks the provider color on the strip it covers`() throws {
        let renderer = MenuBarLayoutRenderer()
        let tint = try #require(MenuBarUsageTint.color(forUsedPercent: 50))
        let output = renderer.render(
            layout: MenuBarLayout(lines: [[.accountLabel, .percent(window: .automatic)]]),
            data: self.data(),
            icon: nil,
            options: self.options(colorByProvider: true, usageColorTarget: .everything))
        let title = output.attributedTitle
        let percentIndex = (title.string as NSString).range(of: "50%").location
        #expect(title.attribute(.foregroundColor, at: percentIndex, effectiveRange: nil) as? NSColor == tint)
        #expect(title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == tint)
    }

    @Test
    func `fork separator pipe layouts migrate to the upstream pipe glyph`() throws {
        let forkJSON = #"{"lines":[[{"icon":{}},{"separatorPipe":{}},{"percent":{"window":"automatic"}}]]}"#
        let migrated = SettingsStore.migratingForkSeparatorPipe(Data(forkJSON.utf8))
        let layout = try JSONDecoder().decode(MenuBarLayout.self, from: migrated)
        #expect(layout.lines == [[.icon, .separator(.pipe), .percent(window: .automatic)]])

        let overrides = #"{"codex":{"lines":[[{"separatorPipe" : { }}, {"usageBar":{}}]]}}"#
        let migratedOverrides = SettingsStore.migratingForkSeparatorPipe(Data(overrides.utf8))
        let decoded = try JSONDecoder().decode([String: MenuBarLayout].self, from: migratedOverrides)
        #expect(decoded["codex"]?.lines == [[.separator(.pipe), .usageBar]])
    }
}
