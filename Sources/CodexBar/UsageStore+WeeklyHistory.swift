import CodexBarCore
import Foundation

extension UsageStore {
    private static let historyWriteMinInterval: TimeInterval = 15 * 60 // 15 minutes
    private static let pruneCheckInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    func recordWeeklyHistoryIfNeeded() {
        let now = Date()
        for provider in self.enabledProviders() {
            self.recordWeeklyHistorySnapshot(for: provider, now: now)
        }
        self.pruneWeeklyHistoryIfNeeded(now: now)
    }

    private func recordWeeklyHistorySnapshot(for provider: UsageProvider, now: Date) {
        // Debounce: at most once per 15 minutes per provider
        let key = "weeklyHistory-\(provider.rawValue)"
        if let lastWrite = self.weeklyHistoryLastWrite[key],
           now.timeIntervalSince(lastWrite) < Self.historyWriteMinInterval
        {
            return
        }

        let snapshot = self.snapshots[provider]
        let tokenSnapshot = self.tokenSnapshots[provider]

        // Need at least some data to record
        guard snapshot?.secondary != nil || tokenSnapshot != nil else { return }

        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone.current
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone.current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let dayKey = dayFormatter.string(from: now)

        let weekNumber = cal.component(.weekOfYear, from: now)
        let weekYear = cal.component(.yearForWeekOfYear, from: now)
        let weekday = cal.component(.weekday, from: now)
        // Convert from Calendar weekday (1=Sun...7=Sat) to ISO 8601 (1=Mon...7=Sun)
        let isoDayOfWeek = weekday == 1 ? 7 : weekday - 1

        // Extract today's token data from the daily entries
        let todayEntry = tokenSnapshot?.daily.first { $0.date == dayKey }

        let record = WeeklyUsageRecord(
            dayKey: dayKey,
            provider: provider,
            weekNumber: weekNumber,
            weekYear: weekYear,
            dayOfWeek: isoDayOfWeek,
            weeklyUsedPercent: snapshot?.secondary?.usedPercent,
            sessionUsedPercent: snapshot?.primary?.usedPercent,
            weeklyResetsAt: snapshot?.secondary?.resetsAt,
            totalTokens: todayEntry?.totalTokens,
            inputTokens: todayEntry?.inputTokens,
            outputTokens: todayEntry?.outputTokens,
            costUSD: todayEntry?.costUSD,
            recordedAt: now)

        WeeklyUsageHistoryStore.save(record: record)
        self.weeklyHistoryLastWrite[key] = now
    }

    private func pruneWeeklyHistoryIfNeeded(now: Date) {
        if let lastPrune = self.weeklyHistoryLastPrune,
           now.timeIntervalSince(lastPrune) < Self.pruneCheckInterval
        {
            return
        }
        self.weeklyHistoryLastPrune = now

        for provider in UsageProvider.allCases {
            WeeklyUsageHistoryStore.prune(provider: provider)
        }
    }
}
