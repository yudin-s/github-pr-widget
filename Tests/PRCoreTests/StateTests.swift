import Foundation

final class StateTests {
    var directory: URL!
    var store: SnapshotStore!
    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try SnapshotStore(directory: directory)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func pr(_ id: String = "p", comments: Set<String> = [], repo: String = "org/repo", number: Int = 1) -> PullRequest {
        PullRequest(id: id, repository: repo, number: number, title: "Test PR", url: "https://github.com/\(repo)/pull/\(number)", review: .required, ci: .none, commentIDs: comments)
    }
    func testBaselineNewCommentReadAndRestart() throws {
        try store.applySync(account: "me", pullRequests: [pr(comments: ["a"])], at: Date())
        try checkEqual(try store.read().unreadCount(for: "p"), 0)
        try store.applySync(account: "me", pullRequests: [pr(comments: ["a", "bot-b"])], at: Date())
        try checkEqual(try store.read().unreadCount(for: "p"), 1)
        try store.markRead(account: "me", prID: "p", displayedCommentIDs: ["a"])
        try checkEqual(try store.read().unreadCount(for: "p"), 1, "A stale card must not mark a later comment read")
        try store.markRead(account: "me", prID: "p", displayedCommentIDs: ["a", "bot-b"])
        try checkEqual(try SnapshotStore(directory: directory).read().unreadCount(for: "p"), 0)
    }
    func testHiddenSurvivesSyncCloseReopenAndAccounts() throws {
        try store.applySync(account: "me", pullRequests: [pr()], at: Date())
        try store.setHidden(account: "me", prID: "p", hidden: true)
        try store.applySync(account: "me", pullRequests: [], at: Date())
        try store.applySync(account: "other", pullRequests: [pr()], at: Date())
        try checkFalse(try store.read().isHidden("p"))
        try store.setHidden(account: "me", prID: "p", hidden: false) // stale account intent: ignored
        try store.applySync(account: "me", pullRequests: [pr()], at: Date())
        try checkTrue(try store.read().isHidden("p"))
        try store.setHidden(account: "me", prID: "p", hidden: false)
        try checkFalse(try store.read().isHidden("p"))
    }
    func testConcurrentWritersDoNotLoseActions() throws {
        try store.applySync(account: "me", pullRequests: [pr()], at: Date())
        let group = DispatchGroup()
        let second = try SnapshotStore(directory: directory)
        let source = pr(comments: ["a"])
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            for _ in 0..<40 { try! second.applySync(account: "me", pullRequests: [source], at: Date()) }
        }
        try store.setHidden(account: "me", prID: "p", hidden: true)
        group.wait()
        try checkTrue(try store.read().isHidden("p"))
        try checkEqual(try store.read().unreadCount(for: "p"), 1)
    }
    func testCorruptionIsNotOverwritten() throws {
        let file = directory.appendingPathComponent("state.json")
        try Data("broken".utf8).write(to: file)
        try checkThrows { _ = try store.read() }
        try checkThrows { try store.applySync(account: "me", pullRequests: [], at: Date()) }
        try checkEqual(try String(contentsOf: file), "broken")
    }
    func testMigrationPreservesPreferencesAndNeverOverwrites() throws {
        let legacy = directory.appendingPathComponent("legacy.json")
        try Data("broken".utf8).write(to: legacy)
        try checkThrows { try store.importIfMissing(from: legacy) }
        try checkFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("state.json").path))
        var snapshot = PRSnapshot()
        snapshot.account = "me"
        snapshot.pullRequests = [pr(comments: ["a", "b"])]
        var preferences = PRPreferences()
        preferences.hidden = true
        preferences.readIDs = ["a"]
        snapshot.accounts = ["me": ["p": preferences]]
        try JSONEncoder().encode(snapshot).write(to: legacy)
        try store.importIfMissing(from: legacy)
        try checkTrue(try store.read().isHidden("p"))
        try checkEqual(try store.read().unreadCount(for: "p"), 1)
        try store.setHidden(account: "me", prID: "p", hidden: false)
        try store.importIfMissing(from: legacy)
        try checkFalse(try store.read().isHidden("p"))
    }
    func testSeparateProcessesPreserveHiddenAndReadState() throws {
        try store.applySync(account: "me", pullRequests: [pr(comments: ["a"])], at: Date())
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--store-writer", directory.path]
        try child.run()
        for _ in 0..<40 {
            try store.setHidden(account: "me", prID: "p", hidden: true)
            try store.markRead(account: "me", prID: "p", displayedCommentIDs: ["a"])
        }
        child.waitUntilExit()
        try checkEqual(child.terminationStatus, 0)
        let result = try store.read()
        try checkTrue(result.isHidden("p"))
        try checkEqual(result.unreadCount(for: "p"), 1)
    }
    func testPaginationIncludesEveryPRAndClampsAfterShrink() throws {
        let prs = (1...12).map { pr("p\($0)", repo: $0 < 4 ? "a/repo" : "b/repo", number: $0) }
        try store.applySync(account: "me", pullRequests: prs, at: Date())
        let snapshot = try store.read()
        var ids: [String] = []
        let first = WidgetPage.make(snapshot: snapshot, hidden: false, index: 0, availableHeight: 240)
        for index in 0..<first.pageCount {
            let page = WidgetPage.make(snapshot: snapshot, hidden: false, index: index, availableHeight: 240)
            let height = page.rows.reduce(0) { sum, row in
                switch row { case .repository: return sum + 16; case .pullRequest: return sum + 46 }
            }
            try checkLessOrEqual(height, 240)
            guard case .repository = page.rows.first else { throw CheckFailure("Missing repository header") }
            ids += page.rows.compactMap { if case let .pullRequest(pr) = $0 { return pr.id }; return nil }
        }
        try checkEqual(first.rows.compactMap { if case let .pullRequest(pr) = $0 { return pr.id }; return nil }, ["p3", "p2", "p1", "p12"])
        try checkEqual(ids.count, 12)
        try checkEqual(Set(ids).count, 12)
        try store.applySync(account: "me", pullRequests: [], at: Date())
        let empty = WidgetPage.make(snapshot: try store.read(), hidden: false, index: 9, availableHeight: 240)
        try checkEqual(empty.index, 0)
        try checkTrue(empty.rows.isEmpty)
    }
    func testRepositoryOrderUsesNewestCommitAndSurvivesRestart() throws {
        func dated(_ id: String, repo: String, number: Int, date: Double?) throws -> PullRequest {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pr(id, repo: repo, number: number))) as! [String: Any]
            json["lastCommitAt"] = date
            return try JSONDecoder().decode(PullRequest.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let requests = try [
            dated("old", repo: "a/old", number: 9, date: 100),
            dated("recent", repo: "z/recent", number: 1, date: 300),
            dated("recent-high", repo: "z/recent", number: 2, date: 50),
            dated("tie", repo: "b/tie", number: 1, date: 300),
            dated("legacy", repo: "a/unknown", number: 1, date: nil)
        ]
        try store.applySync(account: "me", pullRequests: requests, at: Date())
        try store.setHidden(account: "me", prID: "recent", hidden: true)
        let snapshot = try SnapshotStore(directory: directory).read()
        try checkEqual(snapshot.pullRequests.map(\.id), ["tie", "recent-high", "recent", "old", "legacy"])
        let main = WidgetPage.make(snapshot: snapshot, hidden: false, index: 0, availableHeight: 1000)
        try checkEqual(main.rows.compactMap { if case let .repository(repo) = $0 { return repo }; return nil },
                       ["b/tie", "z/recent", "a/old", "a/unknown"])
        try checkTrue(snapshot.isHidden("recent"))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.pullRequests.first { $0.id == "recent" }!)) as! [String: Any]
        try checkEqual(encoded["lastCommitAt"] as? Double, 300)
        try store.applySync(account: "me", pullRequests: requests + [dated("new", repo: "a/old", number: 10, date: 400)], at: Date())
        try checkEqual(try store.read().pullRequests.prefix(2).map(\.id), ["new", "old"])
    }
}
