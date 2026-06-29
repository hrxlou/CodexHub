import AppKit
import Charts
import SwiftUI

struct DashboardCompactView: View {
    @ObservedObject var model: CodexHubModel
    @State private var selectedDays = 30
    @State private var displayedDays = 30
    @State private var showsLoadingChrome = false
    @State private var isAwaitingFirstDashboardLoad = true

    private let ranges = [7, 30, 90, 365]
    private let calendar = Calendar.current
    private let bottomCardContentHeight: CGFloat = 96
    private let bottomAccountCardWidth: CGFloat = 244

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            dashboardContent
        }
        .onAppear {
            if model.dashboardRangeDays == selectedDays {
                displayedDays = selectedDays
            }
            model.loadDashboard(force: false, days: selectedDays)
            updateLoadingPresentation(isLoading: model.isLoadingDashboard)
            if model.isLoadingDashboard == false {
                syncDisplayedDaysIfCurrentSelectionIsLoaded()
                isAwaitingFirstDashboardLoad = false
            }
        }
        .onChange(of: selectedDays) { _, newValue in
            model.loadDashboard(force: false, days: newValue)
            updateLoadingPresentation(isLoading: model.isLoadingDashboard)
            if model.isLoadingDashboard == false {
                syncDisplayedDaysIfCurrentSelectionIsLoaded()
            }
        }
        .onChange(of: model.isLoadingDashboard) { _, isLoading in
            if isLoading == false {
                syncDisplayedDaysIfCurrentSelectionIsLoaded()
                isAwaitingFirstDashboardLoad = false
            }
            updateLoadingPresentation(isLoading: isLoading)
        }
    }

    private var dashboardContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                summaryCard
                trendCard
                bottomGrid
            }
            .opacity(shouldCoverDashboardContent ? 0 : 1)

            loadingOverlay
                .opacity(shouldCoverDashboardContent ? 1 : 0)
                .allowsHitTesting(shouldCoverDashboardContent)
                .zIndex(1)
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var loadingOverlay: some View {
        skeletonDashboard
            .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var shouldCoverDashboardContent: Bool {
        (isAwaitingFirstDashboardLoad && snapshot.isEmpty) ||
            dashboardRangeMismatch ||
            (model.isLoadingDashboard && showsLoadingChrome)
    }

    private var dashboardRangeMismatch: Bool {
        guard snapshot.isEmpty == false, let dashboardRangeDays = model.dashboardRangeDays else { return false }
        return dashboardRangeDays != selectedDays
    }

    private var skeletonDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            skeletonSummaryCard
            skeletonTrendCard
            HStack(alignment: .top, spacing: 12) {
                skeletonAccountCard
                    .frame(width: bottomAccountCardWidth)
                skeletonActivityCard
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(0)
    }

    private var skeletonSummaryCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                skeletonLine(width: 72, height: 12)
                skeletonLine(width: 132, height: 28)
                skeletonLine(width: 82, height: 12)
                skeletonLine(width: 112, height: 26)
            }
            .frame(width: 185, alignment: .leading)

            Divider().opacity(0.28)

            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 10) {
                        skeletonLine(width: 56, height: 13)
                        Spacer()
                        skeletonLine(width: 86, height: 16)
                        skeletonLine(width: 64, height: 13)
                    }
                    .frame(height: 22)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
        .glassPanel(cornerRadius: 8, tint: Color.white.opacity(0.04), stroke: Color.primary.opacity(0.06))
    }

    private var skeletonTrendCard: some View {
        dashboardPanel(title: L.tokenTrend, accessory: model.dashboardProgressText ?? L.loadingUsageDetails) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<18, id: \.self) { index in
                    let height = [22, 58, 16, 84, 34, 104, 18, 24, 68, 28, 76, 20, 42, 62, 30, 90, 46, 26][index]
                    skeletonLine(width: nil, height: CGFloat(height), cornerRadius: 3)
                }
            }
            .frame(height: 128, alignment: .bottom)
        }
    }

    private var skeletonAccountCard: some View {
        dashboardPanel(title: L.byAccount) {
            VStack(spacing: 11) {
                ForEach(0..<3, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            skeletonLine(width: index == 0 ? 126 : 112, height: 12)
                            Spacer()
                            skeletonLine(width: 72, height: 12)
                        }
                        skeletonLine(width: nil, height: 8, cornerRadius: 4)
                    }
                }
            }
            .frame(height: bottomCardContentHeight, alignment: .top)
        }
    }

    private var skeletonActivityCard: some View {
        dashboardPanel(title: L.activityPattern) {
            VStack(spacing: 14) {
                LazyVGrid(columns: activityGridColumns, spacing: 4) {
                    ForEach(0..<30, id: \.self) { _ in
                        skeletonLine(width: activitySquareSize, height: activitySquareSize, cornerRadius: 4)
                    }
                }
                .frame(width: activityGridWidth)
                skeletonLine(width: 150, height: 10)
            }
            .frame(height: bottomCardContentHeight, alignment: .center)
            .frame(maxWidth: .infinity)
        }
    }

    private func skeletonLine(width: CGFloat?, height: CGFloat, cornerRadius: CGFloat = 5) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.075))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }

    private var controls: some View {
        ZStack {
            HStack {
                Spacer()
                Picker("", selection: $selectedDays) {
                    ForEach(ranges, id: \.self) { days in
                        Text(L.days(days)).tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .disabled(model.isLoadingDashboard)
                Spacer()
            }
            HStack {
                Spacer()
                RefreshButton(isRefreshing: model.isLoadingDashboard) {
                    model.loadDashboard(force: true, days: selectedDays)
                }
                .disabled(model.isLoadingDashboard)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func updateLoadingPresentation(isLoading: Bool) {
        if isLoading == false {
            showsLoadingChrome = false
            return
        }

        withAnimation(.easeOut(duration: 0.12)) {
            showsLoadingChrome = true
        }
    }

    private func syncDisplayedDaysIfCurrentSelectionIsLoaded() {
        if model.dashboardRangeDays == selectedDays {
            displayedDays = selectedDays
        }
    }

    private var summaryCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                primaryStat(L.billingTokens, value: Format.preciseTokens(snapshot.total.billingTokenTotal), icon: "number")
                primaryStat(L.totalCost, value: Format.money(snapshot.total.costs.totalCost), icon: "creditcard")
            }
            .frame(width: 185, alignment: .leading)

            Divider().opacity(0.45)

            VStack(spacing: 8) {
                detailUsageRow(L.input, tokens: snapshot.total.totals.billedInputTokens, cost: snapshot.total.costs.inputCost, icon: "tray.and.arrow.down")
                detailUsageRow(L.cache, tokens: snapshot.total.totals.cachedInputTokens, cost: snapshot.total.costs.cachedInputCost, icon: "internaldrive")
                detailUsageRow(L.output, tokens: snapshot.total.totals.outputTokens, cost: snapshot.total.costs.outputCost, icon: "arrow.up.right")
                detailUsageRow(L.reasoning, tokens: snapshot.total.totals.reasoningOutputTokens, cost: snapshot.total.costs.reasoningCost, icon: "brain.head.profile")
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
        .glassPanel(cornerRadius: 8, tint: Color.white.opacity(0.055), stroke: Color.primary.opacity(0.08))
    }

    private var trendCard: some View {
        dashboardPanel(title: L.tokenTrend, accessory: snapshot.scannedFiles > 0 ? L.ledgerRecordCount(snapshot.scannedFiles) : nil) {
            if hasData == false {
                emptyState(height: 128)
            } else {
                Chart(trendPoints) { point in
                    BarMark(
                        x: .value(L.date, point.date, unit: trendDateUnit),
                        y: .value(L.billingTokens, point.aggregate.billingTokenTotal)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.74))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: displayedDays == 7 ? 7 : 6)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Format.chartAxisDate(date, component: trendDateUnit))
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            Text(axisTokenLabel(value))
                        }
                    }
                }
                .frame(height: 128)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
        }
    }

    private var bottomGrid: some View {
        HStack(alignment: .top, spacing: 12) {
            accountCard
                .frame(width: bottomAccountCardWidth)
            activityCard
                .frame(maxWidth: .infinity)
        }
    }

    private var accountCard: some View {
        dashboardPanel(title: L.byAccount) {
            if hasData == false || accountRows.isEmpty {
                emptyState(height: bottomCardContentHeight)
            } else {
                VStack(spacing: 9) {
                    let maxTokens = max(accountRows.map { $0.aggregate.billingTokenTotal }.max() ?? 0, 1)
                    ForEach(Array(accountRows.prefix(3))) { row in
                        accountUsageRow(row, maxTokens: maxTokens)
                    }
                }
                .frame(height: bottomCardContentHeight, alignment: .center)
            }
        }
    }

    private var activityCard: some View {
        dashboardPanel(title: L.activityPattern) {
            if hasData == false || activityPoints.isEmpty {
                emptyState(height: bottomCardContentHeight)
            } else {
                activityPattern
            }
        }
    }

    private var snapshot: DashboardSnapshot {
        model.dashboardSnapshot
    }

    private var hasData: Bool {
        snapshot.isEmpty == false
    }

    private var trendDateUnit: Calendar.Component {
        displayedDays >= 365 ? .month : .day
    }

    private var trendPoints: [DashboardSeriesPoint] {
        switch displayedDays {
        case 0...30:
            return snapshot.dailySeries
        case 31...180:
            return aggregateSeries(component: .weekOfYear)
        default:
            return aggregateSeries(component: .month)
        }
    }

    private var accountRows: [DashboardBreakdown] {
        snapshot.accountBreakdown.map {
            DashboardBreakdown(label: model.displayName(for: $0.label), aggregate: $0.aggregate)
        }
    }

    private var activeDayCount: Int {
        snapshot.dailySeries.filter { $0.aggregate.isZero == false }.count
    }

    private func primaryStat(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func detailUsageRow(_ label: String, tokens: Int, cost: Double, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, alignment: .center)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 36, alignment: .leading)
            }
            .foregroundStyle(.secondary)
            .frame(width: 62, alignment: .leading)
            Text(Format.tokens(tokens))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(Format.money(cost))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 72, alignment: .trailing)
        }
        .frame(height: 23)
    }

    private func accountUsageRow(_ row: DashboardBreakdown, maxTokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Format.summary(row.aggregate))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            GeometryReader { proxy in
                let fraction = CGFloat(row.aggregate.billingTokenTotal) / CGFloat(maxTokens)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.72))
                        .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 8)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var activityPattern: some View {
        VStack(alignment: .center, spacing: 11) {
            HStack {
                Spacer(minLength: 0)
                LazyVGrid(columns: activityGridColumns, spacing: 4) {
                    let maxTokens = max(activityPoints.map { $0.aggregate.billingTokenTotal }.max() ?? 0, 1)
                    ForEach(activityPoints) { point in
                        let intensity = Double(point.aggregate.billingTokenTotal) / Double(maxTokens)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10 + 0.74 * intensity))
                            .frame(width: activitySquareSize, height: activitySquareSize)
                            .help(activityHelp(for: point))
                    }
                }
                .frame(width: activityGridWidth)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                Spacer(minLength: 0)
            }
            Text(activityCaption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(2)
        }
        .frame(height: bottomCardContentHeight, alignment: .center)
        .frame(maxWidth: .infinity)
    }

    private var activityPoints: [DashboardSeriesPoint] {
        switch displayedDays {
        case 0...7:
            return snapshot.activitySeries.isEmpty ? bucketedActivityPoints(targetCount: 30) : snapshot.activitySeries
        case 8...30:
            return snapshot.dailySeries
        default:
            return bucketedActivityPoints(targetCount: 30)
        }
    }

    private var activitySquareSize: CGFloat {
        16
    }

    private var activityColumnCount: Int {
        10
    }

    private var activityGridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(activitySquareSize), spacing: 4), count: max(activityColumnCount, 1))
    }

    private var activityGridWidth: CGFloat {
        let columns = CGFloat(max(activityColumnCount, 1))
        return columns * activitySquareSize + max(0, columns - 1) * 4
    }

    private var activityCaption: String {
        switch displayedDays {
        case 0...7:
            return L.text(ko: "최근 7일 약 6시간 단위 사용 밀도", en: "Approx. 6-hour density over the last 7 days")
        case 8...30:
            return L.text(ko: "최근 30일 일별 사용 밀도", en: "Daily density over the last 30 days")
        case 31...180:
            return L.text(ko: "최근 90일 3일 단위 사용 밀도", en: "3-day density over the last 90 days")
        default:
            return L.text(ko: "최근 365일 약 12일 단위 사용 밀도", en: "Approx. 12-day density over the last 365 days")
        }
    }

    private func bucketedActivityPoints(targetCount: Int) -> [DashboardSeriesPoint] {
        let source = snapshot.dailySeries
        guard source.isEmpty == false else { return [] }

        let bucketCount = max(targetCount, 1)
        var buckets = Array(repeating: UsageAggregate.zero, count: bucketCount)
        var bucketDates = Array(repeating: source[0].date, count: bucketCount)

        for (offset, point) in source.enumerated() {
            let bucketIndex = min(bucketCount - 1, offset * bucketCount / source.count)
            if buckets[bucketIndex].isZero {
                bucketDates[bucketIndex] = point.date
            }
            buckets[bucketIndex] = buckets[bucketIndex].adding(point.aggregate)
        }

        return buckets.indices.map { index in
            DashboardSeriesPoint(date: bucketDates[index], aggregate: buckets[index])
        }
    }

    private func activityHelp(for point: DashboardSeriesPoint) -> String {
        if displayedDays <= 7 {
            return "\(Format.shortDate(point.date)) \(Format.time(point.date)) · \(Format.summary(point.aggregate))"
        }
        return "\(Format.shortDate(point.date)) · \(Format.summary(point.aggregate))"
    }

    private func dashboardPanel<Content: View>(
        title: String,
        accessory: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let accessory {
                    Text(accessory)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 8, tint: Color.white.opacity(0.055), stroke: Color.primary.opacity(0.08))
    }

    private func emptyState(height: CGFloat) -> some View {
        Text(model.isLoadingDashboard && showsLoadingChrome ? L.loadingUsageDetails : L.noUsageInRange)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(height: height, alignment: .center)
            .frame(maxWidth: .infinity)
    }

    private func aggregateSeries(component: Calendar.Component) -> [DashboardSeriesPoint] {
        var grouped: [Date: UsageAggregate] = [:]
        for point in snapshot.dailySeries {
            let key = intervalStart(for: component, date: point.date)
            grouped[key] = (grouped[key] ?? .zero).adding(point.aggregate)
        }
        return grouped
            .map { DashboardSeriesPoint(date: $0.key, aggregate: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func intervalStart(for component: Calendar.Component, date: Date) -> Date {
        switch component {
        case .weekOfYear:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        default:
            return calendar.startOfDay(for: date)
        }
    }

    private func axisTokenLabel(_ value: AxisValue) -> String {
        if let intValue = value.as(Int.self) {
            return Format.tokens(intValue)
        }
        if let doubleValue = value.as(Double.self) {
            return Format.tokens(Int(doubleValue.rounded()))
        }
        return ""
    }
}
