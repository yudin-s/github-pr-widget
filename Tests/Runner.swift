import Foundation
@main struct Checks {
    static func main() async {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--store-writer" {
            do {
                let store = try SnapshotStore(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
                let pr = PullRequest(id: "p", repository: "org/repo", number: 1, title: "Updated",
                                     url: "https://github.com/org/repo/pull/1", review: .approved, ci: .none, commentIDs: ["a", "b"])
                for _ in 0..<40 { try store.applySync(account: "me", pullRequests: [pr], at: Date()) }
                exit(0)
            } catch { print(error); exit(1) }
        }
        let suite = StateTests()
        let cases: [(String, () throws -> Void)] = [
            ("baseline, new comments, stale read and restart", suite.testBaselineNewCommentReadAndRestart),
            ("hidden, reopen and account isolation", suite.testHiddenSurvivesSyncCloseReopenAndAccounts),
            ("concurrent disk writers preserve preferences", suite.testConcurrentWritersDoNotLoseActions),
            ("corruption is not overwritten", suite.testCorruptionIsNotOverwritten),
            ("migration preserves preferences without overwriting", suite.testMigrationPreservesPreferencesAndNeverOverwrites),
            ("separate processes preserve hidden and unread state", suite.testSeparateProcessesPreserveHiddenAndReadState),
            ("pagination retains all PRs", suite.testPaginationIncludesEveryPRAndClampsAfterShrink),
            ("repository order follows latest commits and survives restart", suite.testRepositoryOrderUsesNewestCommitAndSurvivesRestart)
        ]
        var failures = 0
        for (name, test) in cases {
            do { try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        do { try await checkGitHub(); print("PASS GitHub pagination, bots, review state and partial failures") }
        catch { failures += 1; print("FAIL GitHub: \(error)") }
        do { try await checkRefresh(); print("PASS 30-minute schedule, manual refresh, concurrency, error and sleep") }
        catch { failures += 1; print("FAIL refresh: \(error)") }
        do { try await checkProcess(); print("PASS subprocess literal arguments and timeout") }
        catch { failures += 1; print("FAIL subprocess: \(error)") }
        do { try await checkReviewFallback(); print("PASS real approvals when aggregate reviewDecision is null") }
        catch { failures += 1; print("FAIL review fallback: \(error)") }
        print("\(cases.count + 4 - failures)/\(cases.count + 4) checks passed")
        exit(failures == 0 ? 0 : 1)
    }
}
