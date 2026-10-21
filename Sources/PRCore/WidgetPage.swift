import Foundation
public struct WidgetPage: Sendable {
    public enum Row: Identifiable, Sendable {
        case repository(String)
        case pullRequest(PullRequest)
        public var id: String {
            switch self {
            case let .repository(name): return "repo:\(name)"
            case let .pullRequest(pr): return pr.id
            }
        }
    }
    public let rows: [Row]
    public let index: Int
    public let pageCount: Int
    public static let repositoryHeight: Double = 14
    public static let pullRequestHeight: Double = 44
    public static let spacing: Double = 2
    public static func make(snapshot: PRSnapshot, hidden: Bool, index: Int, availableHeight: Double) -> WidgetPage {
        let headerCost = repositoryHeight + spacing
        let rowCost = pullRequestHeight + spacing
        let limit = max(headerCost + rowCost, availableHeight)
        let prs = snapshot.pullRequests.filter { snapshot.isHidden($0.id) == hidden }
        var pages: [[Row]] = []
        var rows: [Row] = []
        var repo: String?
        var usedHeight = 0.0
        for pr in prs {
            let cost = rowCost + (repo == pr.repository ? 0 : headerCost)
            if !rows.isEmpty && usedHeight + cost > limit {
                pages.append(rows); rows = []; repo = nil; usedHeight = 0
            }
            if repo != pr.repository {
                rows.append(.repository(pr.repository)); repo = pr.repository; usedHeight += headerCost
            }
            rows.append(.pullRequest(pr))
            usedHeight += rowCost
        }
        if !rows.isEmpty { pages.append(rows) }
        let clamped = min(max(0, index), max(0, pages.count - 1))
        return WidgetPage(rows: pages.isEmpty ? [] : pages[clamped], index: clamped, pageCount: max(1, pages.count))
    }
}
