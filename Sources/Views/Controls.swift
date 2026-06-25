import SwiftUI

struct ThresholdControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @State private var hoverMinus = false
    @State private var hoverPlus = false
    @State private var textValue = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 6) {
            thresholdButton(symbol: "minus", enabled: value > range.lowerBound, hovering: hoverMinus) {
                value = max(range.lowerBound, value - 5)
                textValue = "\(value)"
            }
            .onHover { hoverMinus = $0 }

            ZStack {
                Text("\(value)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isEditing ? Color.clear : Color.primary)
                    .frame(width: 44, alignment: .center)

                TextField("", text: $textValue)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .foregroundColor(isEditing ? .accentColor : .clear)
                    .accentColor(.accentColor)
                    .frame(width: 44, alignment: .center)
                    .focused($isEditing)
                    .onSubmit {
                        finishEditing()
                        isEditing = false
                    }
                    .onChange(of: textValue) {
                        updateDraft()
                    }
            }
            .frame(width: 58)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(isEditing ? 0.075 : 0.055))
            .overlay(
                Capsule()
                    .stroke(isEditing ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1.5)
            )
            .clipShape(Capsule())

            thresholdButton(symbol: "plus", enabled: value < range.upperBound, hovering: hoverPlus) {
                value = min(range.upperBound, value + 5)
                textValue = "\(value)"
            }
            .onHover { hoverPlus = $0 }
        }
        .padding(3)
        .background(Color.primary.opacity(0.035))
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .clipShape(Capsule())
        .onAppear {
            textValue = "\(value)"
        }
        .onChange(of: value) { _, newValue in
            if !isEditing && textValue != "\(newValue)" {
                textValue = "\(newValue)"
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                textValue = "\(value)"
            } else {
                finishEditing()
            }
        }
    }

    private func updateDraft() {
        let filtered = textValue.filter(\.isNumber)
        if filtered != textValue {
            textValue = filtered
            return
        }

        if filtered.isEmpty {
            return
        }

        guard let parsed = Int(filtered) else { return }
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        if value != clamped {
            value = clamped
        }
    }

    private func finishEditing() {
        let filtered = textValue.filter(\.isNumber)
        guard let parsed = Int(filtered) else {
            textValue = "\(value)"
            return
        }

        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        value = clamped
        textValue = "\(clamped)"
    }

    private func thresholdButton(symbol: String, enabled: Bool, hovering: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.45))
                .background(Color.primary.opacity(enabled ? (hovering ? 0.12 : 0.065) : 0.025))
                .clipShape(Circle())
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}

struct AccountCardView: View {
    @ObservedObject var model: CodexHubModel
    let account: CodexAccount
    @State private var hovering = false

    var body: some View {
        Button {
            guard !account.isActive, !model.isSwitchingAccount else { return }
            model.switchAccount(account.identity)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text(account.isActive ? L.active : L.switchAccount)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(account.isActive ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(account.isActive ? Color.green : Color.primary.opacity(hovering ? 0.12 : 0.07))
                        .clipShape(Capsule())
                    Spacer()
                    Text(account.label)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(account.isActive ? Color.green : Color.secondary)
                }

                Text(model.compactEmail(account.email))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                VStack(spacing: 6) {
                    quotaRow(label: "5H", percent: Format.percentUsed(account.fiveHourUsedPercent), reset: Format.resetTime(from: account.fiveHourUsage))
                    quotaRow(label: "W", percent: Format.percentUsed(account.weeklyUsedPercent), reset: Format.weeklyResetDate(from: account.weeklyUsage))
                }
                .padding(.top, 8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
            .glassPanel(
                tint: accountTint,
                stroke: accountStroke,
                hovering: hovering && !account.isActive
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!account.isActive && !model.isSwitchingAccount)
        .onHover { hovering = $0 }
        .help(account.isActive ? L.activeAccount : L.switchToAccount(account.email))
    }

    private func quotaRow(label: String, percent: String, reset: String) -> some View {
        HStack(alignment: .center, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 24, alignment: .leading)
            Text(percent)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(account.isActive ? Color.green : Color.primary.opacity(0.80))
                .monospacedDigit()
                .frame(width: 58, height: 24, alignment: .leading)
            Spacer()
            Text(reset)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .minimumScaleFactor(0.92)
                .frame(width: 48, height: 24, alignment: .trailing)
        }
    }

    private var accountStroke: Color {
        if account.isActive { return Color.green.opacity(0.30) }
        return Color.primary.opacity(hovering ? 0.22 : 0.08)
    }

    private var accountTint: Color {
        if account.isActive { return Color.green.opacity(0.12) }
        return Color.white.opacity(hovering ? 0.14 : 0.08)
    }
}
