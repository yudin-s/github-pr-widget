import SwiftUI
import WidgetKit
import ServiceManagement

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var snapshot = PRSnapshot()
    @Published var localError: String?
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    private var store: SnapshotStore?
    private var coordinator: RefreshCoordinator?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private init() {
        do {
            let store = try SharedStore.open()
            self.store = store
            try store.recoverInterruptedAttempt()
            coordinator = RefreshCoordinator(client: GitHubClient(), store: store, didChange: {
                WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
                Task { @MainActor in AppModel.shared.reload() }
            })
            reload()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in
                    AppModel.shared.reload()
                    AppModel.shared.refresh(manual: false)
                }
            }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in AppModel.shared.refresh(manual: false) }
            }
            refresh(manual: false)
        } catch { localError = error.localizedDescription }
    }
    func reload() {
        do { if let store { snapshot = try store.read(); localError = nil } }
        catch { localError = "Не удалось прочитать локальные данные: \(error.localizedDescription)" }
    }
    func refresh(manual: Bool = true) {
        guard let coordinator else { return }
        Task { await coordinator.refresh(manual: manual); reload(); if let error = await coordinator.lastError { localError = error } }
    }
    func setHidden(_ pr: PullRequest, hidden: Bool) {
        do { try store?.setHidden(account: snapshot.account, prID: pr.id, hidden: hidden); didChange() }
        catch { localError = error.localizedDescription }
    }
    func markRead(_ pr: PullRequest) {
        do { try store?.markRead(account: snapshot.account, prID: pr.id, displayedCommentIDs: pr.commentIDs); didChange() }
        catch { localError = error.localizedDescription }
    }
    private func didChange() { reload(); WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind) }
    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
        } catch { localError = "Не удалось изменить запуск при входе: \(error.localizedDescription)" }
    }
}
