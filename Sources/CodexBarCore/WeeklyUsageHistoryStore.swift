import Foundation

public enum WeeklyUsageHistoryStore {
    private static let directoryName = "usage-history"

    public static func load(provider: UsageProvider) -> WeeklyUsageReport? {
        guard let url = self.fileURL(for: provider) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? self.decoder.decode(WeeklyUsageReport.self, from: data)
    }

    public static func save(record: WeeklyUsageRecord) {
        let provider = record.provider
        var report = self.load(provider: provider) ?? WeeklyUsageReport()

        // Upsert by dayKey (last-write-wins for same day)
        if let index = report.records.firstIndex(where: { $0.dayKey == record.dayKey }) {
            report.records[index] = record
        } else {
            report.records.append(record)
        }

        guard let url = self.fileURL(for: provider) else { return }
        do {
            let data = try self.encoder.encode(report)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    public static func prune(provider: UsageProvider, keepingWeeks: Int = 12) {
        guard var report = self.load(provider: provider) else { return }
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        guard let cutoff = cal.date(byAdding: .weekOfYear, value: -keepingWeeks, to: now) else { return }
        let cutoffYear = cal.component(.yearForWeekOfYear, from: cutoff)
        let cutoffWeek = cal.component(.weekOfYear, from: cutoff)

        let before = report.records.count
        report.records.removeAll { record in
            if record.weekYear < cutoffYear { return true }
            if record.weekYear == cutoffYear, record.weekNumber < cutoffWeek { return true }
            return false
        }

        guard report.records.count != before else { return }
        guard let url = self.fileURL(for: provider) else { return }
        do {
            let data = try self.encoder.encode(report)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    // MARK: - Private

    private static func fileURL(for provider: UsageProvider) -> URL? {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent(self.directoryName, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(provider.rawValue)-weekly-v1.json", isDirectory: false)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
