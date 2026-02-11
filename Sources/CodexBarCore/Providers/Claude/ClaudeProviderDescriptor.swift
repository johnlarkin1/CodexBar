import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum ClaudeProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .claude,
            metadata: ProviderMetadata(
                id: .claude,
                displayName: "Claude",
                sessionLabel: "Session",
                weeklyLabel: "Weekly",
                opusLabel: "Sonnet",
                supportsOpus: true,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Claude Code usage",
                cliName: "claude",
                defaultEnabled: false,
                isPrimaryProvider: true,
                usesAccountFallback: false,
                browserCookieOrder: ProviderBrowserCookieDefaults.defaultImportOrder,
                dashboardURL: "https://console.anthropic.com/settings/billing",
                subscriptionDashboardURL: "https://claude.ai/settings/usage",
                statusPageURL: "https://status.claude.com/"),
            branding: ProviderBranding(
                iconStyle: .claude,
                iconResourceName: "ProviderIcon-claude",
                color: ProviderColor(red: 204 / 255, green: 124 / 255, blue: 94 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: true,
                noDataMessage: self.noDataMessage),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto],
                pipeline: ProviderFetchPipeline(resolveStrategies: self.resolveStrategies)),
            cli: ProviderCLIConfig(
                name: "claude",
                versionDetector: { browserDetection in
                    ClaudeUsageFetcher(browserDetection: browserDetection).detectVersion()
                }))
    }

    private static func resolveStrategies(context: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        switch context.sourceMode {
        case .api:
            return []
        case .auto, .oauth, .web, .cli:
            return [ClaudeKeychainCLIFetchStrategy()]
        }
    }

    private static func noDataMessage() -> String {
        "No Claude usage logs found in ~/.config/claude/projects or ~/.claude/projects."
    }

    public static func resolveUsageStrategy(
        selectedDataSource: ClaudeUsageDataSource,
        webExtrasEnabled: Bool,
        hasWebSession: Bool,
        hasOAuthCredentials: Bool) -> ClaudeUsageStrategy
    {
        if selectedDataSource == .auto {
            if hasOAuthCredentials {
                return ClaudeUsageStrategy(dataSource: .oauth, useWebExtras: false)
            }
            if hasWebSession {
                return ClaudeUsageStrategy(dataSource: .web, useWebExtras: false)
            }
            return ClaudeUsageStrategy(dataSource: .cli, useWebExtras: false)
        }

        let useWebExtras = selectedDataSource == .cli && webExtrasEnabled && hasWebSession
        return ClaudeUsageStrategy(dataSource: selectedDataSource, useWebExtras: useWebExtras)
    }
}

public struct ClaudeUsageStrategy: Equatable, Sendable {
    public let dataSource: ClaudeUsageDataSource
    public let useWebExtras: Bool
}

/// Fetches Claude usage by reading OAuth credentials from the macOS Keychain via the `/usr/bin/security` CLI.
/// This avoids Keychain permission prompts because the `security` binary is already in the keychain ACL,
/// unlike direct `SecItemCopyMatching` calls which trigger macOS permission dialogs.
struct ClaudeKeychainCLIFetchStrategy: ProviderFetchStrategy {
    let id: String = "claude.keychain-cli"
    let kind: ProviderFetchKind = .oauth

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let credentials = try Self.loadCredentialsViaCLI()
        let usage = try await ClaudeOAuthUsageFetcher.fetchUsage(accessToken: credentials.accessToken)
        let snapshot = try Self.mapUsage(usage, credentials: credentials)
        return self.makeResult(
            usage: snapshot,
            sourceLabel: "keychain-cli")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    // MARK: - Keychain CLI

    private static func loadCredentialsViaCLI() throws -> ClaudeOAuthCredentials {
        if let creds = try? self.runSecurityCLI(service: "Claude Code-credentials") {
            return creds
        }
        return try self.runSecurityCLI(service: "Claude Code")
    }

    private static func runSecurityCLI(service: String) throws -> ClaudeOAuthCredentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? ""
            throw ClaudeUsageError.oauthFailed(
                "Keychain CLI failed for service \"\(service)\": "
                    + errorString.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let jsonString = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !jsonString.isEmpty,
            let jsonData = jsonString.data(using: .utf8)
        else {
            throw ClaudeUsageError.oauthFailed("Empty keychain response for service \"\(service)\"")
        }

        return try ClaudeOAuthCredentials.parse(data: jsonData)
    }

    // MARK: - Usage mapping

    private static func mapUsage(
        _ usage: OAuthUsageResponse,
        credentials: ClaudeOAuthCredentials) throws -> UsageSnapshot
    {
        func makeWindow(_ window: OAuthUsageWindow?, windowMinutes: Int?) -> RateWindow? {
            guard let window, let utilization = window.utilization else { return nil }
            let resetDate = ClaudeOAuthUsageFetcher.parseISO8601Date(window.resetsAt)
            let resetDescription = resetDate.map { UsageFormatter.resetDescription(from: $0) }
            return RateWindow(
                usedPercent: utilization,
                windowMinutes: windowMinutes,
                resetsAt: resetDate,
                resetDescription: resetDescription)
        }

        guard let primary = makeWindow(usage.fiveHour, windowMinutes: 5 * 60) else {
            throw ClaudeUsageError.parseFailed("missing session data")
        }

        let weekly = makeWindow(usage.sevenDay, windowMinutes: 7 * 24 * 60)
        let modelSpecific = makeWindow(
            usage.sevenDaySonnet ?? usage.sevenDayOpus,
            windowMinutes: 7 * 24 * 60)

        let loginMethod = Self.inferPlan(rateLimitTier: credentials.rateLimitTier)
        let providerCost = Self.mapExtraUsageCost(usage.extraUsage, loginMethod: loginMethod)

        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: loginMethod)

        return UsageSnapshot(
            primary: primary,
            secondary: weekly,
            tertiary: modelSpecific,
            providerCost: providerCost,
            updatedAt: Date(),
            identity: identity)
    }

    private static func inferPlan(rateLimitTier: String?) -> String? {
        let tier = rateLimitTier?.lowercased() ?? ""
        if tier.contains("max") { return "Claude Max" }
        if tier.contains("pro") { return "Claude Pro" }
        if tier.contains("team") { return "Claude Team" }
        if tier.contains("enterprise") { return "Claude Enterprise" }
        return nil
    }

    private static func mapExtraUsageCost(
        _ extra: OAuthExtraUsage?,
        loginMethod: String?) -> ProviderCostSnapshot?
    {
        guard let extra, extra.isEnabled == true else { return nil }
        guard let used = extra.usedCredits, let limit = extra.monthlyLimit else { return nil }
        let currency = extra.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = (currency?.isEmpty ?? true) ? "USD" : currency!
        // Claude's OAuth API returns values in cents; convert to dollars.
        var costUsed = used / 100.0
        var costLimit = limit / 100.0
        // Non-enterprise plans may report amounts 100x too high; rescale if limit looks implausible.
        let normalized = loginMethod?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !normalized.contains("enterprise"), costLimit >= 1000 {
            costUsed /= 100.0
            costLimit /= 100.0
        }
        return ProviderCostSnapshot(
            used: costUsed,
            limit: costLimit,
            currencyCode: code,
            period: "Monthly",
            resetsAt: nil,
            updatedAt: Date())
    }
}
