import Foundation

actor ControlledGitHub: GitHubFetching {
    var attempts = 0
    var failure: FetchFailure?
    func setFailure(_ value: FetchFailure?) { failure = value }
    func fetch() async throws -> GitHubResult {
        attempts += 1
        try await Task.sleep(nanoseconds: 40_000_000)
        if let failure { throw failure }
        return GitHubResult(account: "me", pullRequests: [PullRequest(id: "p", repository: "org/repo", number: 1,
            title: "Loaded", url: "https://github.com/org/repo/pull/1", review: .approved, ci: .success)])
    }
}
final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
}
func checkRefresh() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = try SnapshotStore(directory: dir)
    let github = ControlledGitHub(), clock = TestClock()
    let coordinator = RefreshCoordinator(client: github, store: store, now: { clock.now })
    await coordinator.refresh(manual: false)
    try checkEqual(try store.read().pullRequests.first?.title, "Loaded")
    clock.now += 1799
    await coordinator.refresh(manual: false)
    try checkEqual(await github.attempts, 1)
    clock.now += 1
    await coordinator.refresh(manual: false)
    try checkEqual(await github.attempts, 2)
    async let a: Void = coordinator.refresh(manual: true)
    async let b: Void = coordinator.refresh(manual: true)
    async let c: Void = coordinator.refresh(manual: false)
    _ = await (a,b,c)
    try checkEqual(await github.attempts, 3)
    let success = try store.read().lastSuccessAt
    await github.setFailure(FetchFailure("Offline"))
    clock.now += 100
    await coordinator.refresh(manual: true)
    let failed = try store.read()
    try checkEqual(failed.lastSuccessAt, success)
    try checkEqual(failed.pullRequests.first?.title, "Loaded")
    try checkEqual(failed.error, "Offline")
    try checkFalse(failed.isRefreshing)
    await coordinator.refresh(manual: false)
    try checkEqual(await github.attempts, 4)
    await coordinator.refresh(manual: true)
    try checkEqual(await github.attempts, 5)
    await github.setFailure(FetchFailure("Limit", retryAfter: clock.now + 3600))
    await coordinator.refresh(manual: true)
    await coordinator.refresh(manual: true)
    try checkEqual(await github.attempts, 6)
    clock.now += 100_000 // resume after a long sleep: only one request
    await github.setFailure(nil)
    await coordinator.refresh(manual: false)
    await coordinator.refresh(manual: false)
    try checkEqual(await github.attempts, 7)
}

func checkProcess() async throws {
    let result = try await GHProcess(executable: URL(fileURLWithPath: "/usr/bin/printf")).run(arguments: ["%s", "literal $(whoami) `text`"])
    try checkEqual(String(data: result, encoding: .utf8), "literal $(whoami) `text`")
    let started = Date()
    do { _ = try await GHProcess(executable: URL(fileURLWithPath: "/bin/sleep"), timeout: 0.1).run(arguments: ["5"]) }
    catch { try checkTrue(Date().timeIntervalSince(started) < 3); return }
    throw CheckFailure("Timeout did not stop the process")
}
