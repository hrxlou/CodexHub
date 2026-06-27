import AppKit
import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: CodexHubModel
    @State private var selectedDays = 30
    @State private var showsLoadingChrome = false
    @State private var loadingChromeToken = 0

    private let ranges = [30, 90, 365]

    var body: some View {
        ScrollView {
            dashboardContent
        }
        .background(
            ZStack {
                Rectangle().fill(.thinMaterial)
                Color.white.opacity(0.045)
            }
        )
        .frame(minWidth: 900, minHeight: 640)
        .onAppear {
            model.loadDashboard(force: false, days: selectedDays)
            updateLoadingPresentation(isLoading: model.isLoadingDashboard)
        }
        .onChange(of: selectedDays) { _, newValue in
            model.loadDashboard(force: false, days: newValue)
        }
        .onChange(of: model.isLoadingDashboard) { _, isLoading in
            updateLoadingPresentation(isLoading: isLoading)
        }
    }

    private var dashboardContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryGrid
                trendPanel
                breakdownGrid
                heatmapPanel
            }
            .opacity(shouldCoverDashboardContent ? 0 : 1)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }

            if shouldCoverDashboardContent {
                dashboardLoadingOverlay
                    .zIndex(1)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shouldCoverDashboardContent: Bool {
        model.isLoadingDashboard && showsLoadingChrome
    }

    private var dashboardLoadingOverlay: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            skeletonSummaryGrid
            skeletonPanel(title: L.tokenTrend, height: 240)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                skeletonPanel(title: L.byAccount, height: 240)
                skeletonPanel(title: L.byModel, height: 240)
            }
            skeletonPanel(title: L.last30Days, height: 130)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var skeletonSummaryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        skeletonLine(width: 16, height: 16, cornerRadius: 4)
                        Spacer()
                    }
                    skeletonLine(width: 72, height: 12)
                    skeletonLine(width: index == 0 ? 108 : 132, height: 24)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                .glassPanel(cornerRadius: 8, tint: Color.white.opacity(0.055), stroke: Color.primary.opacity(0.08))
            }
        }
    }

    private func skeletonPanel(title: String, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ProgressView(value: model.dashboardProgress ?? 0, total: 1)
                        .progressViewStyle(.linear)
                    Text("\(Int(((model.dashboardProgress ?? 0) * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let progressText = model.dashboardProgressText {
                    Text(progressText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<12, id: \.self) { index in
                        skeletonLine(width: nil, height: CGFloat(28 + (index % 5) * 18), cornerRadius: 5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
            .frame(height: height, alignment: .topLeading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 8, tint: Color.white.opacity(0.055), stroke: Color.primary.opacity(0.08))
    }

    private func skeletonLine(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 4) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.075))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }

    private func updateLoadingPresentation(isLoading: Bool) {
        loadingChromeToken += 1
        let token = loadingChromeToken

        if isLoading == false {
            showsLoadingChrome = false
            return
        }

        showsLoadingChrome = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard token == loadingChromeToken, model.isLoadingDashboard else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                showsLoadingChrome = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: HubImages.appIconLight)
                .resizable()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(L.dashboard)
                    .font(.system(size: 22, weight: .semibold))
                Text(Format.relative(model.dashboardSnapshot.lastUpdatedAt))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $selectedDays) {
                ForEach(ranges, id: \.self) { days in
                    Text(L.days(days)).tag(days)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 236)
            .disabled(model.isLoadingDashboard)
            RefreshButton(isRefreshing: model.isLoadingDashboard) {
                model.loadDashboard(force: true, days: selectedDays)
            }
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            summaryTile(L.totalCost, Format.money(model.dashboardSnapshot.total.costs.totalCost), "creditcard")
            summaryTile(L.billingTokens, Format.tokens(model.dashboardSnapshot.total.billingTokenTotal), "number")
            summaryTile(L.input, Format.tokens(model.dashboardSnapshot.total.totals.billedInputTokens), "tray.and.arrow.down")
            summaryTile(L.output, Format.tokens(model.dashboardSnapshot.total.totals.outputTokens), "arrow.up.right")
        }
    }

    private var trendPanel: some View {
        dashboardPanel(title: L.tokenTrend) {
            if loadingOrEmpty {
                dashboardPlaceholder
            } else {
                Chart(model.dashboardSnapshot.dailySeries) { point in
                    BarMark(
                        x: .value(L.date, point.date, unit: .day),
                        y: .value(L.billingTokens, point.aggregate.billingTokenTotal)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.76))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 240)
            }
        }
    }

    private var breakdownGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            breakdownPanel(title: L.byAccount, rows: displayAccountBreakdown)
            breakdownPanel(title: L.byModel, rows: model.dashboardSnapshot.modelBreakdown)
        }
    }

    private var heatmapPanel: some View {
        dashboardPanel(title: L.last30Days) {
            if loadingOrEmpty {
                dashboardPlaceholder
            } else {
                let maxTokens = max(model.dashboardSnapshot.calendarHeatmap.map { $0.aggregate.billingTokenTotal }.max() ?? 0, 1)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 5), count: 10), spacing: 5) {
                    ForEach(model.dashboardSnapshot.calendarHeatmap) { day in
                        let intensity = Double(day.aggregate.billingTokenTotal) / Double(maxTokens)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12 + 0.72 * intensity))
                            .frame(width: 22, height: 22)
                            .help("\(Format.shortDate(day.date)) · \(Format.summary(day.aggregate))")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var dashboardPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isLoadingDashboard {
                HStack(spacing: 10) {
                    ProgressView(value: model.dashboardProgress ?? 0, total: 1)
                        .progressViewStyle(.linear)
                    Text("\(Int(((model.dashboardProgress ?? 0) * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let progressText = model.dashboardProgressText {
                    Text(progressText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L.noDashboardData)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 130, alignment: .center)
    }

    private var loadingOrEmpty: Bool {
        model.isLoadingDashboard || model.dashboardSnapshot.isEmpty
    }

    private var displayAccountBreakdown: [DashboardBreakdown] {
        model.dashboardSnapshot.accountBreakdown.map {
            DashboardBreakdown(label: model.displayName(for: $0.label), aggregate: $0.aggregate)
        }
    }

    private func summaryTile(_ title: String, _ value: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .glassPanel(cornerRadius: 8, tint: Color.white.opacity(0.055), stroke: Color.primary.opacity(0.08))
    }

    private func breakdownPanel(title: String, rows: [DashboardBreakdown]) -> some View {
        dashboardPanel(title: title) {
            if loadingOrEmpty || rows.isEmpty {
                dashboardPlaceholder
            } else {
                Chart(Array(rows.prefix(8))) { row in
                    BarMark(
                        x: .value(L.billingTokens, row.aggregate.billingTokenTotal),
                        y: .value(title, row.label)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.76))
                }
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 240)
            }
        }
    }

    private func dashboardPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if model.dashboardSnapshot.scannedFiles > 0 {
                    Text(L.ledgerRecordCount(model.dashboardSnapshot.scannedFiles))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 8, tint: Color.white.opacity(0.055), stroke: Color.primary.opacity(0.08))
    }
}
