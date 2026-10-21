import Foundation

public enum ReviewStatus: String, Codable, Sendable {
    case draft, approved, changesRequested, required, none
    public var label: String {
        switch self {
        case .draft: return "Draft"
        case .approved: return "Approved"
        case .changesRequested: return "Нужны правки"
        case .required: return "Ждёт ревью"
        case .none: return "Ждёт ревью"
        }
    }
    public var symbol: String {
        switch self {
        case .draft: return "pencil.circle"
        case .approved: return "checkmark.seal.fill"
        case .changesRequested: return "exclamationmark.bubble.fill"
        case .required: return "clock"
        case .none: return "clock"
        }
    }
}
public enum CIStatus: String, Codable, Sendable {
    case success, failure, pending, none, unknown
    public var label: String {
        switch self {
        case .success: return "CI ✓"
        case .failure: return "CI ✕"
        case .pending: return "CI …"
        case .none: return "Без CI"
        case .unknown: return "CI ?"
        }
    }
}
public struct PullRequest: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var repository: String
    public var number: Int
    public var title: String
    public var url: String
    public var review: ReviewStatus
    public var ci: CIStatus
    public var commentIDs: Set<String>
    public var lastCommitAt: Date?
    public init(id: String, repository: String, number: Int, title: String, url: String,
                review: ReviewStatus, ci: CIStatus, commentIDs: Set<String> = [], lastCommitAt: Date? = nil) {
        self.id = id; self.repository = repository; self.number = number; self.title = title
        self.url = url; self.review = review; self.ci = ci; self.commentIDs = commentIDs
        self.lastCommitAt = lastCommitAt
    }
}
public struct PRPreferences: Codable, Sendable {
    public var hidden = false
    public var readIDs: Set<String> = []
    public init() {}
}
public struct PRSnapshot: Codable, Sendable {
    public var version = 1
    public var account = ""
    public var pullRequests: [PullRequest] = []
    public var accounts: [String: [String: PRPreferences]] = [:]
    public var lastSuccessAt: Date?
    public var lastAttemptAt: Date?
    public var nextAttemptAt: Date?
    public var rateLimitUntil: Date?
    public var isRefreshing = false
    public var error: String?
    public var showHidden = false
    public var pageIndex = 0
    public init() {}
    public func isHidden(_ id: String) -> Bool { accounts[account]?[id]?.hidden ?? false }
    public func unreadCount(for id: String) -> Int {
        guard let pr = pullRequests.first(where: { $0.id == id }) else { return 0 }
        return pr.commentIDs.subtracting(accounts[account]?[id]?.readIDs ?? pr.commentIDs).count
    }
    public var hiddenCount: Int { pullRequests.filter { isHidden($0.id) }.count }
    public var unreadTotal: Int { pullRequests.reduce(0) { $0 + unreadCount(for: $1.id) } }
}
