import Foundation
#if canImport(PRCore)
import PRCore
#endif

public actor RefreshCoordinator {
    private let client: any GitHubFetching
    private let store: SnapshotStore
    private let now: @Sendable () -> Date
    private let didChange: @Sendable () -> Void
    private var inFlight: Task<Void, Never>?
    public private(set) var lastError: String?
    public init(client: any GitHubFetching, store: SnapshotStore,
                now: @escaping @Sendable () -> Date = { Date() },
                didChange: @escaping @Sendable () -> Void = {}) {
        self.client = client; self.store = store; self.now = now; self.didChange = didChange
    }
    public func refresh(manual: Bool) async {
        if let inFlight { await inFlight.value; return }
        do {
            let snapshot = try store.read()
            if let limit = snapshot.rateLimitUntil, now() < limit { return }
            if !manual, let next = snapshot.nextAttemptAt, now() < next { return }
        } catch { lastError = "Не удалось прочитать локальные данные: \(error.localizedDescription)"; didChange(); return }
        let task = Task { await performRefresh() }
        inFlight = task
        await task.value
        inFlight = nil
    }
    private func performRefresh() async {
        lastError = nil
        do {
            try store.beginAttempt(at: now()); didChange()
            let result = try await client.fetch()
            try store.applySync(account: result.account, pullRequests: result.pullRequests, at: now())
        } catch {
            let message = (error as? FetchFailure)?.message ?? "Не удалось обновить данные: \(error.localizedDescription)"
            lastError = message
            do { try store.failAttempt(message: message, at: now(), retryAfter: (error as? FetchFailure)?.retryAfter) }
            catch { lastError = "Не удалось сохранить состояние: \(error.localizedDescription)" }
        }
        didChange()
    }
}
