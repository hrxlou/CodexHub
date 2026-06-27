import SwiftUI

extension CodexHubMenu {
    var tokenCostDetails: some View {
        DashboardCompactView(model: model)
    }

    var usageDetailsProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.loadingUsageDetails)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let progress = model.usageDetailsProgress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: model.usageDetailsProgress ?? 0, total: 1)
                .progressViewStyle(.linear)

            if let progressText = model.usageDetailsProgressText {
                Text(progressText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    func tokenCostSummaryCard(_ details: UsageDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.tokenCost)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L.ledgerRecordCount(details.scannedFiles))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            detailSummaryRow(L.today, aggregate: details.today)
            detailSummaryRow(L.thisWeek, aggregate: details.week)
            detailSummaryRow(L.thisMonth, aggregate: details.month)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 10, tint: Color.white.opacity(0.065), stroke: Color.primary.opacity(0.075))
    }

    func accountUsageSection(title: String, usage: [String: UsageAggregate], maxRows: Int? = nil) -> some View {
        sectionCard(title: title) {
            let rows = model.sortedAccountUsageRows(usage)
            let visibleRows = Array(rows.prefix(maxRows ?? rows.count))
            if rows.isEmpty {
                Text(L.noAttributedUsage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleRows, id: \.email) { row in
                    compactUsageRow(label: model.displayName(for: row.email), value: Format.summary(row.aggregate))
                }
                if visibleRows.count < rows.count {
                    compactUsageRow(label: L.more(rows.count - visibleRows.count), value: "")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func compactUsageRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .font(.system(size: 11))
    }

    private func detailSummaryRow(_ label: String, aggregate: UsageAggregate) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Format.summary(aggregate))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
    }
}
