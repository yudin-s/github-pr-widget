import SwiftUI
import WidgetKit

struct PRWidgetView: View {
    let snapshot: PRSnapshot
    var body: some View {
        GeometryReader { geometry in
            let page = WidgetPage.make(snapshot: snapshot, hidden: snapshot.showHidden, index: snapshot.pageIndex, availableHeight: geometry.size.height - 64)
            VStack(alignment: .leading, spacing: WidgetPage.spacing) {
                HStack {
                    Label("GitHub PR", systemImage: "arrow.triangle.branch").font(.headline)
                    Spacer()
                    Text("\(snapshot.pullRequests.count)").foregroundStyle(.secondary)
                    Button(intent: RefreshPRIntent()) {
                        Image(systemName: "arrow.clockwise").frame(width: 24, height: 20).contentShape(Rectangle())
                    }
                        .accessibilityLabel("Обновить GitHub PR")
                }
                HStack(spacing: 4) {
                    if snapshot.isRefreshing { Text("Обновление…") }
                    else if snapshot.error != nil { Image(systemName: "exclamationmark.triangle"); Text("Ошибка обновления") }
                    else if !snapshot.account.isEmpty { Text("@\(snapshot.account)") }
                    if let date = snapshot.lastSuccessAt { Spacer(); Text(date, style: .time) }
                }.font(.caption2).foregroundStyle(snapshot.error == nil ? Color.secondary : Color.orange)
                Divider()
                if page.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(emptyTitle).font(.subheadline)
                        if let error = snapshot.error { Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    ForEach(page.rows) { row in
                        switch row {
                        case let .repository(repo): Text(repo).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).frame(height: WidgetPage.repositoryHeight)
                        case let .pullRequest(pr): prRow(pr)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Divider()
                HStack {
                    Button(intent: ShowPRPageIntent(hidden: !snapshot.showHidden, page: 0)) {
                        Text(snapshot.showHidden ? "Back" : "More (\(snapshot.hiddenCount))")
                            .frame(minWidth: 64, minHeight: 20, alignment: .leading).contentShape(Rectangle())
                    }
                    Spacer()
                    if page.pageCount > 1 {
                        // Disabled widget buttons fall through to macOS's open-app action.
                        // Keep boundary buttons interactive and target the current page.
                        Button(intent: ShowPRPageIntent(hidden: snapshot.showHidden, page: max(0, page.index - 1))) {
                            Image(systemName: "chevron.left").opacity(page.index == 0 ? 0.35 : 1)
                                .frame(width: 24, height: 20).contentShape(Rectangle())
                        }.accessibilityLabel(page.index == 0 ? "Первая страница" : "Предыдущая страница")
                        Text("\(page.index + 1)/\(page.pageCount)").monospacedDigit().font(.caption)
                        Button(intent: ShowPRPageIntent(hidden: snapshot.showHidden, page: min(page.pageCount - 1, page.index + 1))) {
                            Image(systemName: "chevron.right").opacity(page.index + 1 == page.pageCount ? 0.35 : 1)
                                .frame(width: 24, height: 20).contentShape(Rectangle())
                        }.accessibilityLabel(page.index + 1 == page.pageCount ? "Последняя страница" : "Следующая страница")
                    }
                }.font(.caption)
            }.buttonStyle(.plain)
        }
    }
    private var emptyTitle: String {
        if snapshot.lastSuccessAt == nil { return "Откройте приложение и подключите GitHub через gh auth login." }
        if snapshot.showHidden { return "Скрытых PR нет" }
        return snapshot.hiddenCount > 0 ? "Все PR в More" : "Нет открытых PR"
    }
    private func prRow(_ pr: PullRequest) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                if let url = URL(string: pr.url) {
                    Link(destination: url) { Text("#\(pr.number) \(pr.title)").font(.caption).lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                }
                HStack(spacing: 6) {
                    Label(pr.review.label, systemImage: pr.review.symbol)
                        .foregroundStyle(pr.review == .approved ? Color.green : pr.review == .changesRequested ? Color.orange : Color.secondary)
                    Text(pr.ci.label).foregroundStyle(pr.ci == .failure ? Color.red : Color.secondary)
                }.font(.caption2).lineLimit(1)
            }
            if snapshot.unreadCount(for: pr.id) > 0 {
                Button(intent: ReadPRIntent(account: snapshot.account, prID: pr.id, commentIDs: Array(pr.commentIDs).sorted())) {
                    Text("\(snapshot.unreadCount(for: pr.id))").font(.caption2.bold()).foregroundStyle(.blue)
                        .frame(minWidth: 24, minHeight: 24).contentShape(Rectangle())
                }.accessibilityLabel("\(snapshot.unreadCount(for: pr.id)) новых комментариев. Отметить прочитанным")
            }
            Button(intent: HidePRIntent(account: snapshot.account, prID: pr.id, hidden: !snapshot.showHidden)) {
                Image(systemName: snapshot.showHidden ? "eye" : "eye.slash").font(.caption2)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }.accessibilityLabel(snapshot.showHidden ? "Вернуть PR" : "Скрыть PR")
        }.frame(height: WidgetPage.pullRequestHeight, alignment: .top)
    }
}
