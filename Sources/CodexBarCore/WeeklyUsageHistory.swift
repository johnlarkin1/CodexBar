import Foundation

/// A single daily snapshot combining API percentage data and local token data for weekly tracking.
public struct WeeklyUsageRecord: Codable, Sendable, Equatable {
    public let dayKey: String // "2026-02-11"
    public let provider: UsageProvider
    public let weekNumber: Int // ISO 8601 week-of-year
    public let weekYear: Int // ISO 8601 year-for-week-of-year
    public let dayOfWeek: Int // 1=Mon ... 7=Sun

    // From RateWindow (percentage-based, from API)
    public let weeklyUsedPercent: Double?
    public let sessionUsedPercent: Double?
    public let weeklyResetsAt: Date?

    // From CostUsageTokenSnapshot (token-based, from local logs)
    public let totalTokens: Int?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let costUSD: Double?

    public let recordedAt: Date

    public init(
        dayKey: String,
        provider: UsageProvider,
        weekNumber: Int,
        weekYear: Int,
        dayOfWeek: Int,
        weeklyUsedPercent: Double?,
        sessionUsedPercent: Double?,
        weeklyResetsAt: Date?,
        totalTokens: Int?,
        inputTokens: Int?,
        outputTokens: Int?,
        costUSD: Double?,
        recordedAt: Date)
    {
        self.dayKey = dayKey
        self.provider = provider
        self.weekNumber = weekNumber
        self.weekYear = weekYear
        self.dayOfWeek = dayOfWeek
        self.weeklyUsedPercent = weeklyUsedPercent
        self.sessionUsedPercent = sessionUsedPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.recordedAt = recordedAt
    }
}

/// Container for weekly usage records with query helpers.
public struct WeeklyUsageReport: Codable, Sendable {
    public var records: [WeeklyUsageRecord]

    public init(records: [WeeklyUsageRecord] = []) {
        self.records = records
    }

    public func currentWeek(now: Date = Date()) -> [WeeklyUsageRecord] {
        let cal = Calendar(identifier: .iso8601)
        let year = cal.component(.yearForWeekOfYear, from: now)
        let week = cal.component(.weekOfYear, from: now)
        return self.week(year: year, number: week)
    }

    public func previousWeek(now: Date = Date()) -> [WeeklyUsageRecord] {
        let cal = Calendar(identifier: .iso8601)
        guard let oneWeekAgo = cal.date(byAdding: .weekOfYear, value: -1, to: now) else { return [] }
        let year = cal.component(.yearForWeekOfYear, from: oneWeekAgo)
        let week = cal.component(.weekOfYear, from: oneWeekAgo)
        return self.week(year: year, number: week)
    }

    public func week(year: Int, number: Int) -> [WeeklyUsageRecord] {
        self.records.filter { $0.weekYear == year && $0.weekNumber == number }
            .sorted { $0.dayOfWeek < $1.dayOfWeek }
    }
}
