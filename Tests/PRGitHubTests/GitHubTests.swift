import Foundation

actor FixtureGH: GHExecuting {
    var mode: String
    init(_ mode: String = "ok") { self.mode = mode }
    func run(arguments: [String]) async throws -> Data {
        if arguments.contains("user") { return Data("{\"login\":\"me\"}".utf8) }
        if arguments.contains("graphql") {
            if mode == "graphql-error" { return Data("{\"errors\":[{\"message\":\"denied\"}]}".utf8) }
            let second = arguments.contains("cursor=next")
            let cursor = mode == "cursor-loop" ? "next" : (second ? "" : "next")
            let more = mode == "cursor-loop" || !second
            let login = mode == "account-change" && second ? "other" : "me"
            let decision = mode.hasPrefix("fallback-") ? "null" : "\"CHANGES_REQUESTED\""
            return Data("""
            {"data":{"viewer":{"login":"\(login)","pullRequests":{"pageInfo":{"hasNextPage":\(more),"endCursor":"\(cursor)"},"nodes":[{"id":"p\(second ? 2 : 1)","number":\(second ? 2 : 1),"title":"PR","url":"https://github.com/o/r/pull/1","isDraft":false,"reviewDecision":\(decision),"repository":{"nameWithOwner":"o/r"},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-21T10:09:17Z","statusCheckRollup":{"state":"FAILURE"}}}]}}]}}}}
            """.utf8)
        }
        guard arguments.contains("--paginate"), arguments.contains("--slurp") else { throw CheckFailure("Comments must be fully paginated") }
        let endpoint = arguments.last!
        if mode == "partial-error" && endpoint.contains("pulls/2/reviews") { throw FetchFailure("Offline") }
        if endpoint.contains("/issues/") {
            return Data("""
            [[{"node_id":"c1","user":{"login":"me"},"body":"own"}], [{"node_id":"c2","user":{"login":"copilot[bot]"},"body":"finding"}]]
            """.utf8)
        }
        if endpoint.contains("/reviews") {
            if mode.hasPrefix("fallback-") {
                var reviews: [[String: Any]] = [
                    ["node_id":"old", "user":["login":"reviewer"], "body":"", "state":"DISMISSED", "submitted_at":"2026-10-19T14:38:54Z"],
                    ["node_id":"current", "user":["login":"reviewer"], "body":"", "state":mode == "fallback-dismissed" ? "DISMISSED" : "APPROVED", "submitted_at":"2026-10-21T07:03:01Z"]
                ]
                if mode == "fallback-commented" { reviews.append(["node_id":"comment", "user":["login":"reviewer"], "body":"follow-up", "state":"COMMENTED", "submitted_at":"2026-10-21T08:00:00Z"]) }
                if mode == "fallback-changes" { reviews.append(["node_id":"changes", "user":["login":"another"], "body":"fix", "state":"CHANGES_REQUESTED", "submitted_at":"2026-10-21T08:00:00Z"]) }
                if mode == "fallback-dismissed-latest" { reviews.append(["node_id":"withdrawn", "user":["login":"reviewer"], "body":"", "state":"DISMISSED", "submitted_at":"2026-10-21T08:00:00Z"]) }
                if mode == "fallback-own" { reviews = [["node_id":"own", "user":["login":"me"], "body":"", "state":"APPROVED"]] }
                return try JSONSerialization.data(withJSONObject: [reviews])
            }
            return Data("""
            [[{"node_id":"r1","user":{"login":"reviewer"},"body":"historical approval","state":"APPROVED"},{"node_id":"r2","user":{"login":"reviewer"},"body":"","state":"APPROVED"},{"node_id":"r3","user":{"login":"reviewer"},"body":"not published","state":"PENDING"}]]
            """.utf8)
        }
        return Data("""
        [[{"node_id":"c3","user":null,"body":"deleted author"},{"node_id":"c4","user":{"login":"reviewer"},"body":"inline"}]]
        """.utf8)
    }
}
func checkReviewFallback() async throws {
    for (mode, expected) in [("fallback-approved", ReviewStatus.approved), ("fallback-dismissed", .none),
                             ("fallback-commented", .approved), ("fallback-changes", .changesRequested), ("fallback-own", .none), ("fallback-dismissed-latest", .none)] {
        let result = try await GitHubClient(executor: FixtureGH(mode)).fetch()
        try checkEqual(result.pullRequests[0].review, expected, mode)
    }
}
func checkGitHub() async throws {
    let result = try await GitHubClient(executor: FixtureGH()).fetch()
    try checkEqual(result.account, "me")
    try checkEqual(result.pullRequests.count, 2)
    try checkEqual(result.pullRequests[0].commentIDs, ["c2", "c3", "c4", "r1"])
    try checkEqual(result.pullRequests[0].review, .changesRequested)
    try checkEqual(result.pullRequests[0].ci, .failure)
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result.pullRequests[0])) as! [String: Any]
    try checkEqual(encoded["lastCommitAt"] as? Double, ISO8601DateFormatter().date(from: "2026-10-21T10:09:17Z")!.timeIntervalSinceReferenceDate)
    for mode in ["graphql-error", "partial-error", "account-change", "cursor-loop"] {
        do { _ = try await GitHubClient(executor: FixtureGH(mode)).fetch() }
        catch { continue }
        throw CheckFailure("\(mode) returned a misleading complete result")
    }
}
