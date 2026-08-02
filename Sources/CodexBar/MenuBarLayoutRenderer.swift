import AppKit
import CodexBarCore
import Foundation

struct MenuBarLayoutRenderWindow: Hashable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let resetDescription: String?

    init?(_ window: RateWindow?) {
        guard let window, !window.isSyntheticPlaceholder else { return nil }
        self.usedPercent = window.usedPercent
        self.windowMinutes = window.windowMinutes
        self.resetsAt = window.resetsAt
        self.resetDescription = window.resetDescription
    }

    var remainingPercent: Double {
        max(0, 100 - self.usedPercent)
    }
}

struct MenuBarLayoutRenderData: Hashable {
    let iconKey: String
    let providerName: String?
    let accountLabel: String?
    let session: MenuBarLayoutRenderWindow?
    let weekly: MenuBarLayoutRenderWindow?
    let automatic: MenuBarLayoutRenderWindow?
    let sessionPace: String?
    let weeklyPace: String?
    let runsOut: String?
    let costToday: String?
    let cost30d: String?
}

extension MenuBarLayoutRenderData {
    /// Whether every usage-bearing token in `layout` has a value to show.
    ///
    /// Identity and money tokens are excluded on purpose: those go missing because the user turned them off
    /// (`hidePersonalInfo`, cost tracking), which is not the same as the provider having no data to preview.
    func populates(_ layout: MenuBarLayout) -> Bool {
        layout.lines.allSatisfy { line in
            line.allSatisfy { token in
                switch token {
                case let .percent(window):
                    MenuBarLayoutRenderer.window(window, data: self) != nil
                case let .pace(window):
                    MenuBarLayoutRenderer.pace(window, data: self) != nil
                case .usageBar:
                    self.automatic != nil
                case .resetCountdown, .resetAbsolute:
                    self.automatic?.resetsAt != nil || self.automatic?.resetDescription != nil
                case .runsOut:
                    self.runsOut != nil
                case .icon, .providerName, .accountLabel, .costToday, .cost30d,
                     .separatorDot, .separatorPipe, .space:
                    true
                }
            }
        }
    }
}

struct MenuBarLayoutRenderOptions: Hashable {
    let size: MenuBarLayoutSize
    let highContrast: Bool
    let showUsed: Bool
    let appearanceName: String
    let isDebugApp: Bool
    /// Minute-granularity clock. Countdown tokens refresh without invalidating cached titles every tick.
    let now: Date
    /// Which tokens carry the usage tint, or `nil` when color-coded usage is off.
    let usageColorTarget: MenuBarUsageColorTarget?
}

struct MenuBarLayoutRenderKey: Hashable {
    let layout: MenuBarLayout
    let data: MenuBarLayoutRenderData
    let options: MenuBarLayoutRenderOptions
}

struct MenuBarLayoutRenderedTitle {
    let attributedTitle: NSAttributedString
    let accessibilityLabel: String
}

@MainActor
final class MenuBarLayoutTitleCache {
    private let capacity: Int
    private var storage: [MenuBarLayoutRenderKey: MenuBarLayoutRenderedTitle] = [:]

    init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    func value(
        for key: MenuBarLayoutRenderKey,
        make: () -> MenuBarLayoutRenderedTitle)
        -> MenuBarLayoutRenderedTitle
    {
        if let cached = self.storage[key] {
            return cached
        }
        let value = make()
        if self.storage.count >= self.capacity, let oldest = self.storage.keys.first {
            self.storage.removeValue(forKey: oldest)
        }
        self.storage[key] = value
        return value
    }

    func removeAll() {
        self.storage.removeAll(keepingCapacity: true)
    }

    var count: Int {
        self.storage.count
    }
}

@MainActor
final class MenuBarLayoutRenderer {
    private static let missingValue = "–"
    private static let stackedBaselineOffset: CGFloat = -3 // Center multi-line NSStatusBarButton titles.

    private struct TokenStyle {
        let font: NSFont
        let iconTint: NSColor
        /// `true` when `iconTint` is a usage color rather than the dynamic label color, which means the
        /// attachment has to stop being a template image or AppKit repaints it back to the label color.
        let iconTintIsUsageColor: Bool
        let iconHeight: CGFloat
        let attributes: [NSAttributedString.Key: Any]
        /// Attributes for tokens whose value the usage tint restates. Identical to `attributes` unless the
        /// color target singles those tokens out.
        let usageAttributes: [NSAttributedString.Key: Any]
        /// Windows that already have a `.percent` token somewhere in the strip. A `.pace` token for the same
        /// window drops its prefix rather than repeating a label the strip already carries.
        let windowsLabeledByPercentToken: Set<PercentWindow>
    }

    private let cache: MenuBarLayoutTitleCache

    init(cache: MenuBarLayoutTitleCache = MenuBarLayoutTitleCache()) {
        self.cache = cache
    }

    func render(
        layout: MenuBarLayout,
        data: MenuBarLayoutRenderData,
        icon: NSImage?,
        options: MenuBarLayoutRenderOptions)
        -> MenuBarLayoutRenderedTitle
    {
        let key = MenuBarLayoutRenderKey(layout: layout, data: data, options: options)
        return self.cache.value(for: key) {
            Self.renderUncached(layout: layout, data: data, icon: icon, options: options)
        }
    }

    func removeAll() {
        self.cache.removeAll()
    }

    private static func renderUncached(
        layout: MenuBarLayout,
        data: MenuBarLayoutRenderData,
        icon: NSImage?,
        options: MenuBarLayoutRenderOptions)
        -> MenuBarLayoutRenderedTitle
    {
        let isStacked = layout.lines.count == 2
        let font = NSFont.systemFont(ofSize: Self.fontSize(size: options.size, isStacked: isStacked))
        let baseColor = options.highContrast ? NSColor.labelColor : NSColor.controlTextColor
        // The strip has no single meter to read, so the tint follows whichever window the layout would show
        // first. `automatic` is what the default layout renders; session/weekly cover strips that skip it.
        let usageTint = options.usageColorTarget == nil
            ? nil
            : MenuBarUsageTint.color(
                forUsedPercent: (data.automatic ?? data.session ?? data.weekly)?.usedPercent)
        let foregroundColor = options.usageColorTarget == .everything ? usageTint ?? baseColor : baseColor
        let paragraphStyle = NSMutableParagraphStyle()
        if isStacked {
            paragraphStyle.minimumLineHeight = 9.5
            paragraphStyle.maximumLineHeight = 9.5
            paragraphStyle.lineSpacing = -1
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle,
        ]
        if isStacked {
            attributes[.baselineOffset] = Self.stackedBaselineOffset
        }
        var usageAttributes = attributes
        if options.usageColorTarget == .usage, let usageTint {
            usageAttributes[.foregroundColor] = usageTint
        }
        // Every target tints the icon: it is the one token that always reads as "this provider's usage", so
        // leaving it uncolored while the numbers beside it are colored looks like a rendering bug.
        // The targets differ only in how much text they carry beyond it.
        let style = TokenStyle(
            font: font,
            iconTint: usageTint ?? foregroundColor,
            iconTintIsUsageColor: usageTint != nil,
            iconHeight: Self.iconHeight(size: options.size, isStacked: isStacked),
            attributes: attributes,
            usageAttributes: usageAttributes,
            windowsLabeledByPercentToken: Self.windowsLabeledByPercentToken(in: layout))
        let result = NSMutableAttributedString()
        var accessibilityLines: [String] = []

        for (lineIndex, line) in layout.lines.enumerated() {
            if lineIndex > 0 {
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            var accessibilityParts: [String] = []
            for (tokenIndex, token) in line.enumerated() {
                if tokenIndex > 0, token != .space, line[tokenIndex - 1] != .space {
                    result.append(NSAttributedString(string: "\u{2009}", attributes: attributes))
                }
                let renderedItem = Self.renderItem(
                    token,
                    data: data,
                    icon: icon,
                    style: style,
                    options: options)
                result.append(renderedItem.value)
                if let accessibilityText = renderedItem.accessibilityText {
                    accessibilityParts.append(accessibilityText)
                }
            }
            accessibilityLines.append(accessibilityParts.joined(separator: ", "))
        }

        if options.isDebugApp {
            result.append(NSAttributedString(string: " D", attributes: attributes))
            accessibilityLines[accessibilityLines.count - 1].append(", \(L("Debug"))")
        }
        let accessibilityLabel = accessibilityLines.enumerated().map { index, line in
            index == 0 ? line : "\(L("menu_bar_layout_line", index + 1)), \(line)"
        }.joined(separator: ", ")
        return MenuBarLayoutRenderedTitle(
            attributedTitle: result,
            accessibilityLabel: accessibilityLabel)
    }

    private static func renderItem(
        _ item: MenuBarLayoutToken,
        data: MenuBarLayoutRenderData,
        icon: NSImage?,
        style: TokenStyle,
        options: MenuBarLayoutRenderOptions)
        -> (value: NSAttributedString, accessibilityText: String?)
    {
        switch item {
        case .icon:
            guard let icon else {
                return self.textToken(
                    self.missingValue,
                    accessibilityText: L("Icon unavailable"),
                    attributes: style.attributes)
            }
            let attachment = NSTextAttachment()
            attachment.image = Self.attachmentImage(
                icon,
                tint: style.iconTint,
                keepsTemplate: !style.iconTintIsUsageColor)
            let height = style.iconHeight
            let width = icon.size.height > 0 ? icon.size.width * height / icon.size.height : height
            attachment.bounds = NSRect(
                x: 0,
                y: ((style.font.capHeight - height) / 2).rounded(),
                width: width,
                height: height)
            let value = NSMutableAttributedString(attachment: attachment)
            value.addAttributes(style.attributes, range: NSRange(location: 0, length: value.length))
            return (value, L("%@ icon", data.providerName ?? L("Provider")))
        case .providerName:
            return self.optionalTextToken(
                data.providerName,
                unavailableLabel: L("Provider name unavailable"),
                attributes: style.attributes)
        case .accountLabel:
            return self.optionalTextToken(
                data.accountLabel,
                unavailableLabel: L("Account unavailable"),
                attributes: style.attributes)
        case let .percent(window):
            let rateWindow = Self.window(window, data: data)
            let percent = rateWindow.map { options.showUsed ? $0.usedPercent : $0.remainingPercent }
            let value = percent.map(UsageFormatter.percentString) ?? Self.missingValue
            let prefix = Self.prefix(for: window)
            let accessibilityPrefix: String = switch window {
            case .session: L("Session")
            case .weekly: L("Weekly")
            case .automatic: L("Usage")
            }
            let display = prefix.isEmpty ? value : "\(prefix) \(value)"
            let accessibility = percent == nil
                ? L("%@ unavailable", accessibilityPrefix)
                : L("%@ %@", accessibilityPrefix, value)
            return self.textToken(display, accessibilityText: accessibility, attributes: style.usageAttributes)
        case let .pace(window):
            return self.paceToken(window, data: data, style: style)
        case .usageBar:
            guard let window = data.automatic else {
                return self.textToken(
                    self.missingValue,
                    accessibilityText: L("Usage bar unavailable"),
                    attributes: style.attributes)
            }
            let displayedPercent = options.showUsed ? window.usedPercent : window.remainingPercent
            let filled = Int((displayedPercent.clamped(to: 0...100) / 100 * 3).rounded())
            let value = String(repeating: "▮", count: filled) + String(repeating: "▯", count: 3 - filled)
            return self.textToken(
                value,
                accessibilityText: L("Usage bar, %d of 3 filled", filled),
                attributes: style.usageAttributes)
        case .resetCountdown:
            return self.resetToken(
                data.automatic?.resetsAt.map { UsageFormatter.resetCountdownDescription(from: $0, now: options.now) }
                    ?? data.automatic?.resetDescription,
                unavailableLabel: L("Reset countdown unavailable"),
                attributes: style.attributes)
        case .resetAbsolute:
            return self.resetToken(
                data.automatic?.resetsAt.map { UsageFormatter.resetDescription(from: $0, now: options.now) }
                    ?? data.automatic?.resetDescription,
                unavailableLabel: L("Reset time unavailable"),
                attributes: style.attributes)
        case .runsOut:
            return self.optionalTextToken(
                data.runsOut,
                unavailableLabel: L("Run-out estimate unavailable"),
                attributes: style.usageAttributes)
        case .costToday:
            return self.optionalTextToken(
                data.costToday,
                unavailableLabel: L("Cost today unavailable"),
                attributes: style.attributes)
        case .cost30d:
            return self.optionalTextToken(
                data.cost30d,
                unavailableLabel: L("30-day cost unavailable"),
                attributes: style.attributes)
        case .separatorDot:
            return self.textToken("·", accessibilityText: nil, attributes: style.attributes)
        case .separatorPipe:
            return self.textToken("|", accessibilityText: nil, attributes: style.attributes)
        case .space:
            return self.textToken(" ", accessibilityText: nil, attributes: style.attributes)
        }
    }

    private static func attachmentImage(_ image: NSImage, tint: NSColor, keepsTemplate: Bool) -> NSImage {
        guard image.isTemplate else { return image }

        // NSTextAttachment draws an NSImage directly instead of through an image cell, so AppKit does not
        // apply template tinting here. Keep a template image for status-item semantics while drawing its mask
        // with the same dynamic foreground color as the surrounding title.
        let tintedImage = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            tint.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        // A usage tint has to survive as-drawn: AppKit repaints template images in the label color, which
        // would throw the color away. Baking it in is the same trade the meter icon makes.
        tintedImage.isTemplate = keepsTemplate
        return tintedImage
    }

    private static func windowsLabeledByPercentToken(in layout: MenuBarLayout) -> Set<PercentWindow> {
        var windows: Set<PercentWindow> = []
        for line in layout.lines {
            for token in line {
                if case let .percent(window) = token {
                    windows.insert(window)
                }
            }
        }
        return windows
    }

    private static func resetToken(
        _ value: String?,
        unavailableLabel: String,
        attributes: [NSAttributedString.Key: Any])
        -> (value: NSAttributedString, accessibilityText: String?)
    {
        self.optionalTextToken(
            value,
            unavailableLabel: unavailableLabel,
            accessibilityPrefix: L("Resets"),
            attributes: attributes)
    }

    private static func optionalTextToken(
        _ value: String?,
        unavailableLabel: String,
        accessibilityPrefix: String? = nil,
        attributes: [NSAttributedString.Key: Any])
        -> (value: NSAttributedString, accessibilityText: String?)
    {
        guard let value, !value.isEmpty else {
            return self.textToken(self.missingValue, accessibilityText: unavailableLabel, attributes: attributes)
        }
        let accessibilityText = accessibilityPrefix.map { "\($0) \(value)" } ?? value
        return self.textToken(value, accessibilityText: accessibilityText, attributes: attributes)
    }

    private static func textToken(
        _ value: String,
        accessibilityText: String?,
        attributes: [NSAttributedString.Key: Any])
        -> (value: NSAttributedString, accessibilityText: String?)
    {
        (NSAttributedString(string: value, attributes: attributes), accessibilityText)
    }

    fileprivate nonisolated static func window(
        _ percentWindow: PercentWindow,
        data: MenuBarLayoutRenderData)
        -> MenuBarLayoutRenderWindow?
    {
        switch percentWindow {
        case .session: data.session
        case .weekly: data.weekly
        case .automatic: data.automatic
        }
    }

    /// Pace reuses the percent token's window vocabulary so a strip carrying both reads consistently — but it
    /// drops the prefix when the strip already labels that window, so `S 11% | S +20%` reads `S 11% | +20%`.
    /// Only the compact pace delta is shown; the run-out estimate that shares the same pace calculation stays
    /// in the dedicated `.runsOut` token, and the prose form stays in the dropdown.
    private static func paceToken(
        _ window: PercentWindow,
        data: MenuBarLayoutRenderData,
        style: TokenStyle)
        -> (value: NSAttributedString, accessibilityText: String?)
    {
        let accessibilityPrefix: String = switch window {
        case .session: L("Session pace")
        case .weekly: L("Weekly pace")
        case .automatic: L("Pace")
        }
        guard let paceValue = Self.pace(window, data: data) else {
            return self.textToken(
                self.missingValue,
                accessibilityText: L("%@ unavailable", accessibilityPrefix),
                attributes: style.usageAttributes)
        }
        let prefix = style.windowsLabeledByPercentToken.contains(window) ? "" : Self.prefix(for: window)
        return self.textToken(
            prefix.isEmpty ? paceValue : "\(prefix) \(paceValue)",
            accessibilityText: L("%@ %@", accessibilityPrefix, paceValue),
            attributes: style.usageAttributes)
    }

    fileprivate nonisolated static func pace(
        _ percentWindow: PercentWindow,
        data: MenuBarLayoutRenderData)
        -> String?
    {
        switch percentWindow {
        case .session: data.sessionPace
        case .weekly: data.weeklyPace
        // Providers without a session-length pace fall back to the weekly figure so the automatic token
        // stays populated instead of collapsing to the unavailable placeholder.
        case .automatic: data.sessionPace ?? data.weeklyPace
        }
    }

    /// Disambiguates two usage tokens in one strip. Deliberately a letter and not the window duration: `5h 11%`
    /// reads as a countdown rather than as "11% of the 5-hour window", which is the opposite of what it means.
    private static func prefix(for window: PercentWindow) -> String {
        switch window {
        case .session: "S"
        case .weekly: "W"
        case .automatic: ""
        }
    }

    private static func fontSize(size: MenuBarLayoutSize, isStacked: Bool) -> CGFloat {
        if isStacked {
            return size == .small ? 8 : 9
        }
        return size == .small ? 11 : NSFont.systemFontSize
    }

    private static func iconHeight(size: MenuBarLayoutSize, isStacked: Bool) -> CGFloat {
        if isStacked {
            return size == .small ? 8 : 9
        }
        return size == .small ? 14 : 16
    }
}
