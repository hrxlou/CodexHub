import SwiftUI

extension CodexHubMenu {
    func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 10, tint: Color.white.opacity(0.065), stroke: Color.primary.opacity(0.075))
    }
}
