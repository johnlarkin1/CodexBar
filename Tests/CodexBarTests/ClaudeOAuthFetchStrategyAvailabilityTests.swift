import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
@Suite(.serialized)
struct ClaudeKeychainCLIFetchStrategyTests {
    private func makeContext(sourceMode: ProviderSourceMode) -> ProviderFetchContext {
        let env: [String: String] = [:]
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: nil,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: BrowserDetection(cacheTTL: 0)),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }

    @Test
    func keychainCLIStrategyAlwaysAvailable() async {
        let context = self.makeContext(sourceMode: .auto)
        let strategy = ClaudeKeychainCLIFetchStrategy()
        let available = await strategy.isAvailable(context)
        #expect(available == true)
    }

    @Test
    func keychainCLIStrategyNeverFallsBack() {
        let context = self.makeContext(sourceMode: .auto)
        let strategy = ClaudeKeychainCLIFetchStrategy()
        #expect(strategy.shouldFallback(
            on: ClaudeUsageError.oauthFailed("test"),
            context: context) == false)
    }
}
#endif
