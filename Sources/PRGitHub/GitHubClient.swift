import Foundation
#if canImport(PRCore)
import PRCore
#endif

public struct FetchFailure: LocalizedError, Sendable {
    public let message: String
    public let retryAfter: Date?
    public init(_ message: String, retryAfter: Date? = nil) { self.message = message; self.retryAfter = retryAfter }
    public var errorDescription: String? { message }
}
public protocol GHExecuting: Sendable {
    func run(arguments: [String]) async throws -> Data
}
public struct GitHubResult: Sendable {
    public let account: String
    public let pullRequests: [PullRequest]
    public init(account: String, pullRequests: [PullRequest]) { self.account = account; self.pullRequests = pullRequests }
}
public protocol GitHubFetching: Sendable { func fetch() async throws -> GitHubResult }
public struct GitHubClient: GitHubFetching {
    private let executor: any GHExecuting
    public init(executor: any GHExecuting = GHProcess()) { self.executor = executor }
    private static let query = """
    query($cursor:String){viewer{login pullRequests(first:50,after:$cursor,states:OPEN,orderBy:{field:UPDATED_AT,direction:DESC}){pageInfo{hasNextPage endCursor} nodes{id number title url isDraft reviewDecision repository{nameWithOwner} commits(last:1){nodes{commit{committedDate statusCheckRollup{state}}}}}}}}
    """
    private struct Connection: Decodable {
        let pageInfo: PageInfo
        let nodes: [Node]
    }
    private struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }
    private struct Node: Decodable {
        let id: String; let number: Int; let title: String; let url: String
        let isDraft: Bool; let reviewDecision: String?
        let repository: Repository; let commits: Commits
        struct Repository: Decodable { let nameWithOwner: String }
        struct Commits: Decodable {
            let nodes: [CommitNode]
            struct CommitNode: Decodable {
                let commit: Commit
                struct Commit: Decodable {
                    let committedDate: Date?
                    let statusCheckRollup: Rollup?
                    struct Rollup: Decodable { let state: String }
                }
            }
        }
    }
    private struct Response: Decodable {
        let data: Payload?
        let errors: [GraphError]?
        struct GraphError: Decodable { let message: String }
        struct Payload: Decodable {
            let viewer: Viewer
            struct Viewer: Decodable { let login: String; let pullRequests: Connection }
        }
    }
    private struct Comment: Decodable {
        let node_id: String
        let user: User?
        let body: String?
        let state: String?
        let submitted_at: String?
        struct User: Decodable { let login: String }
    }
    public func fetch() async throws -> GitHubResult {
        var cursor: String?
        var visited = Set<String>()
        var account: String?
        var nodes: [Node] = []
        repeat {
            var args = ["api", "--hostname", "github.com", "graphql", "-f", "query=\(Self.query)"]
            if let cursor { args += ["-f", "cursor=\(cursor)"] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(Response.self, from: await executor.run(arguments: args))
            guard response.errors?.isEmpty ?? true, let viewer = response.data?.viewer else {
                throw FetchFailure("GitHub вернул неполные данные. Проверьте доступ аккаунта к репозиториям.")
            }
            let login = viewer.login.lowercased()
            if let account, account != login { throw FetchFailure("Аккаунт gh сменился во время обновления. Повторите запрос.") }
            account = login
            nodes += viewer.pullRequests.nodes
            if viewer.pullRequests.pageInfo.hasNextPage {
                guard let next = viewer.pullRequests.pageInfo.endCursor, !next.isEmpty,
                      visited.insert(next).inserted else { throw FetchFailure("GitHub не вернул следующую страницу PR.") }
                cursor = next
            } else { cursor = nil }
        } while cursor != nil
        guard let account else { throw FetchFailure("Не удалось определить аккаунт GitHub.") }
        var requests: [PullRequest] = []
        var seenPRs = Set<String>()
        for node in nodes where seenPRs.insert(node.id).inserted {
            let repo = node.repository.nameWithOwner
            var comments = Set<String>()
            var opinions: [String: String] = [:]
            for path in ["issues/\(node.number)/comments", "pulls/\(node.number)/comments", "pulls/\(node.number)/reviews"] {
                let data = try await executor.run(arguments: ["api", "--hostname", "github.com", "--paginate", "--slurp", "repos/\(repo)/\(path)?per_page=100"])
                let pages = try JSONDecoder().decode([[Comment]].self, from: data)
                if path.hasSuffix("/reviews") {
                    // COMMENTED does not revoke an earlier approval or change request.
                    // The latest withdrawn opinion also supersedes an older opinion by that reviewer.
                    let ordered = pages.flatMap({ $0 }).enumerated().sorted {
                        let lhs = $0.element.submitted_at ?? "", rhs = $1.element.submitted_at ?? ""
                        return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
                    }
                    for (_, review) in ordered {
                        guard let author = review.user?.login.lowercased(), author != account,
                              let state = review.state, ["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].contains(state) else { continue }
                        opinions[author] = state
                    }
                }
                for comment in pages.flatMap({ $0 }) where comment.user?.login.lowercased() != account {
                    if comment.state == "PENDING" { continue }
                    guard !(comment.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    comments.insert(comment.node_id)
                }
            }
            let review: ReviewStatus
            if node.isDraft { review = .draft }
            else {
                switch node.reviewDecision {
                case "APPROVED": review = .approved
                case "CHANGES_REQUESTED": review = .changesRequested
                case "REVIEW_REQUIRED": review = .required
                default:
                    if opinions.values.contains("CHANGES_REQUESTED") { review = .changesRequested }
                    else if opinions.values.contains("APPROVED") { review = .approved }
                    else { review = .none }
                }
            }
            let ci: CIStatus
            switch node.commits.nodes.first?.commit.statusCheckRollup?.state {
            case "SUCCESS": ci = .success
            case "FAILURE", "ERROR": ci = .failure
            case "PENDING", "EXPECTED": ci = .pending
            case nil: ci = .none
            default: ci = .unknown
            }
            requests.append(PullRequest(id: node.id, repository: repo, number: node.number,
                                        title: node.title, url: node.url, review: review, ci: ci, commentIDs: comments,
                                        lastCommitAt: node.commits.nodes.first?.commit.committedDate))
        }
        struct User: Decodable { let login: String }
        let user = try JSONDecoder().decode(User.self, from: await executor.run(arguments: ["api", "--hostname", "github.com", "user"]))
        guard user.login.lowercased() == account else { throw FetchFailure("Аккаунт gh сменился во время обновления.") }
        return GitHubResult(account: account, pullRequests: requests)
    }
}
