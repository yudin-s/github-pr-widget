import SwiftUI

@main struct GitHubPRApp: App {
    @StateObject private var model = AppModel.shared
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("GitHub PR", id: "dashboard") {
            DashboardView(model: model)
                .onOpenURL { url in if url.scheme == "github-pr-widget" { model.refresh() } }
        }
        .defaultSize(width: 800, height: 620)
        MenuBarExtra("GitHub PR", systemImage: "arrow.triangle.branch") {
            Text(model.snapshot.account.isEmpty ? "GitHub PR" : "@\(model.snapshot.account) · \(model.snapshot.pullRequests.count) PR")
            Button("Открыть список") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
            Button("Обновить") { model.refresh() }.disabled(model.snapshot.isRefreshing)
            Divider()
            Button("Завершить GitHub PR") { NSApp.terminate(nil) }
        }
        Settings {
            Form {
                Toggle("Запускать при входе в macOS", isOn: Binding(get: { model.loginEnabled }, set: { enabled in model.setLoginEnabled(enabled) }))
                Text("Обновление каждые 30 минут, пока приложение работает. Ручная кнопка доступна в списке и виджете.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("GitHub", value: model.snapshot.account.isEmpty ? "Не подключён" : "@\(model.snapshot.account)")
                Text("Авторизация: gh auth login в Терминале.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).frame(width: 440, height: 230)
        }
    }
}
