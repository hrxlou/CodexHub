import SwiftUI

@main
struct CodexHubApp: App {
    @StateObject private var model = CodexHubModel()

    var body: some Scene {
        MenuBarExtra {
            CodexHubMenu(model: model)
                .onAppear {
                    model.refresh(force: false)
                }
        } label: {
            Text(model.menuBarTitle)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
