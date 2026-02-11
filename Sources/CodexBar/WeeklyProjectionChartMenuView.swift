import Charts
import CodexBarCore
import SwiftUI

@MainActor
struct WeeklyProjectionChartMenuView: View {
    private let provider: UsageProvider
    private let projection: WeeklyProjection
    private let width: CGFloat
    @State private var selectedDay: Int?

    init(provider: UsageProvider, projection: WeeklyProjection, width: CGFloat) {
        self.provider = provider
        self.projection = projection
        self.width = width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if self.projection.points.isEmpty {
                Text("Previous week data will appear after one week of use.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    // Last week's trajectory (dashed)
                    ForEach(self.lastWeekSeries, id: \.dayOfWeek) { point in
                        LineMark(
                            x: .value("Day", point.dayOfWeek),
                            y: .value("Value", point.value))
                            .foregroundStyle(self.mutedColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .symbol(Circle())
                            .symbolSize(16)
                    }
                    .accessibilityLabel("Last week")

                    // This week's actual data (solid)
                    ForEach(self.thisWeekSeries, id: \.dayOfWeek) { point in
                        LineMark(
                            x: .value("Day", point.dayOfWeek),
                            y: .value("Value", point.value))
                            .foregroundStyle(self.brandColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .symbol(Circle())
                            .symbolSize(20)

                        AreaMark(
                            x: .value("Day", point.dayOfWeek),
                            y: .value("Value", point.value))
                            .foregroundStyle(self.brandColor.opacity(0.1))
                    }
                    .accessibilityLabel("This week")

                    // Projection (dotted, future days)
                    ForEach(self.projectedSeries, id: \.dayOfWeek) { point in
                        LineMark(
                            x: .value("Day", point.dayOfWeek),
                            y: .value("Value", point.value))
                            .foregroundStyle(self.brandColor.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                            .symbol {
                                Circle()
                                    .strokeBorder(self.brandColor.opacity(0.5), lineWidth: 1)
                                    .frame(width: 5, height: 5)
                            }
                    }
                    .accessibilityLabel("Projected")
                }
                .chartXAxis {
                    AxisMarks(values: Array(1...7)) { value in
                        AxisGridLine().foregroundStyle(Color.clear)
                        AxisTick().foregroundStyle(Color.clear)
                        AxisValueLabel {
                            if let day = value.as(Int.self), day >= 1, day <= 7 {
                                Text(Self.dayLabels[day - 1])
                                    .font(.caption2)
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 130)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        MouseLocationReader { location in
                            self.updateSelection(location: location, proxy: proxy, geo: geo)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(self.detailPrimary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: 16, alignment: .leading)
                    Text(self.detailSecondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: 16, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Series

    private struct SeriesPoint {
        let dayOfWeek: Int
        let value: Double
    }

    private var thisWeekSeries: [SeriesPoint] {
        self.projection.points.compactMap { point in
            guard let value = point.thisWeekValue else { return nil }
            return SeriesPoint(dayOfWeek: point.dayOfWeek, value: value)
        }
    }

    private var lastWeekSeries: [SeriesPoint] {
        self.projection.points.compactMap { point in
            guard let value = point.lastWeekValue else { return nil }
            return SeriesPoint(dayOfWeek: point.dayOfWeek, value: value)
        }
    }

    private var projectedSeries: [SeriesPoint] {
        // Include the last actual data point as the start of the projection line
        var series: [SeriesPoint] = []
        let lastActual = self.thisWeekSeries.last
        if let lastActual {
            series.append(lastActual)
        }
        for point in self.projection.points {
            guard let value = point.projectedValue else { continue }
            series.append(SeriesPoint(dayOfWeek: point.dayOfWeek, value: value))
        }
        return series
    }

    // MARK: - Colors

    private var brandColor: Color {
        let color = ProviderDescriptorRegistry.descriptor(for: self.provider).branding.color
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private var mutedColor: Color {
        self.brandColor.opacity(0.35)
    }

    // MARK: - Detail text

    private static let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var detailPrimary: String {
        if let day = self.selectedDay, day >= 1, day <= 7 {
            let point = self.projection.points[day - 1]
            let label = Self.dayLabels[day - 1]
            let thisWeek = point.thisWeekValue.map { Self.formatValue($0, metric: self.projection.metric) } ?? "—"
            let lastWeek = point.lastWeekValue.map { Self.formatValue($0, metric: self.projection.metric) } ?? "—"
            if point.projectedValue != nil {
                let projected = Self.formatValue(point.projectedValue!, metric: self.projection.metric)
                return "\(label): projected \(projected) (last week: \(lastWeek))"
            }
            return "\(label): \(thisWeek) (last week: \(lastWeek))"
        }
        return self.summaryText
    }

    private var detailSecondary: String {
        if self.selectedDay != nil {
            return " "
        }
        return self.projectionSummaryText
    }

    private var summaryText: String {
        let thisWeek = self.projection.thisWeekTotal.map {
            Self.formatValue($0, metric: self.projection.metric)
        } ?? "—"
        let lastWeek = self.projection.lastWeekTotal.map {
            Self.formatValue($0, metric: self.projection.metric)
        } ?? "—"
        let changeText = if let change = self.projection.changePercent {
            String(format: " (%+.0f%%)", change)
        } else {
            ""
        }
        return "This week: \(thisWeek) vs last week: \(lastWeek)\(changeText)"
    }

    private var projectionSummaryText: String {
        guard let projected = self.projection.projectedEndOfWeek else {
            return "Hover for day details"
        }
        let formatted = Self.formatValue(projected, metric: self.projection.metric)
        return "Projected end of week: \(formatted)"
    }

    private static func formatValue(_ value: Double, metric: WeeklyProjection.Metric) -> String {
        switch metric {
        case .percentage:
            String(format: "%.0f%%", value)
        case .tokens:
            UsageFormatter.tokenCountString(Int(value))
        case .cost:
            UsageFormatter.usdString(value)
        }
    }

    // MARK: - Hover

    private func updateSelection(location: CGPoint?, proxy: ChartProxy, geo: GeometryProxy) {
        guard let location else {
            if self.selectedDay != nil { self.selectedDay = nil }
            return
        }

        guard let plotAnchor = proxy.plotFrame else { return }
        let plotFrame = geo[plotAnchor]
        guard plotFrame.contains(location) else { return }

        let xInPlot = location.x - plotFrame.origin.x
        guard let rawDay: Int = proxy.value(atX: xInPlot) else { return }
        let day = max(1, min(7, rawDay))

        if self.selectedDay != day {
            self.selectedDay = day
        }
    }
}
