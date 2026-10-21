import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var showMore = false
    private var snapshot: PRSnapshot { model.snapshot }
    private var visible: [PullRequest] { snapshot.pullRequests.filter { !snapshot.isHidden($0.id) } }
    private var hidden: [PullRequest] { snapshot.pullRequests.filter { snapshot.isHidden($0.id) } }
    var body: some View {
        VStack(spacing: 0) {
            if let error = model.localError ?? snapshot.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).textSelection(.enabled)
                    Spacer()
                }.font(.callout).padding().background(.quaternary)
                Divider()
            }
            if snapshot.pullRequests.isEmpty {
                ContentUnavailableView {
                    Label(snapshot.lastSuccessAt == nil ? "Подключение к GitHub" : "Нет открытых PR", systemImage: "arrow.triangle.branch")
                } description: {
                    Text(snapshot.lastSuccessAt == nil ? "Используется текущий аккаунт GitHub CLI. Если вход ещё не выполнен, запустите gh auth login в Терминале." : "Здесь появятся ваши открытые pull requests из всех доступных репозиториев.")
                } actions: { Button("Обновить") { model.refresh() }.disabled(snapshot.isRefreshing) }
            } else {
                List {
                    ForEach(repositories(in: visible), id: \.self) { repo in
                        Section(repo) {
                            ForEach(visible.filter { $0.repository == repo }) { pr in row(pr, hidden: false) }
                        }
                    }
                    if visible.isEmpty { Text("Все PR скрыты. Откройте More, чтобы вернуть их.").foregroundStyle(.secondary) }
                    Section {
                        DisclosureGroup(isExpanded: $showMore) {
                            if hidden.isEmpty { Text("Скрытых PR нет").foregroundStyle(.secondary) }
                            ForEach(repositories(in: hidden), id: \.self) { repo in
                                Text(repo).font(.headline).foregroundStyle(.secondary)
                                ForEach(hidden.filter { $0.repository == repo }) { pr in row(pr, hidden: true) }
                            }
                        } label: { Text("More (\(hidden.count))") }
                    }
                }.listStyle(.inset)
            }
            Divider()
            HStack {
                if snapshot.isRefreshing { ProgressView().controlSize(.small); Text("Обновление…") }
                else if let date = snapshot.lastSuccessAt { Text("Обновлено \(date.formatted(date: .omitted, time: .shortened))") }
                else { Text("Данные ещё не загружены") }
                Spacer()
                Text("Каждые 30 минут")
            }.font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .frame(minWidth: 620, minHeight: 420)
        .navigationTitle("GitHub PR")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text(snapshot.account.isEmpty ? "" : "@\(snapshot.account) · \(snapshot.pullRequests.count) PR").foregroundStyle(.secondary)
            }
            ToolbarItem {
                Button { model.refresh() } label: { Label("Обновить", systemImage: "arrow.clockwise") }
                    .disabled(snapshot.isRefreshing).keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem { SettingsLink { Label("Настройки", systemImage: "gearshape") } }
        }
    }
    private func repositories(in requests: [PullRequest]) -> [String] {
        var seen = Set<String>()
        return requests.map(\.repository).filter { seen.insert($0).inserted }
    }
    private func row(_ pr: PullRequest, hidden: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: pr.review.symbol).foregroundStyle(pr.review == .approved ? .green : pr.review == .changesRequested ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 5) {
                if let url = URL(string: pr.url) { Link(pr.title, destination: url).font(.body).lineLimit(2) }
                HStack(spacing: 12) {
                    Text("#\(pr.number)")
                    Text(pr.review.label)
                    Text(pr.ci.label).foregroundStyle(pr.ci == .failure ? .red : .secondary)
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if snapshot.unreadCount(for: pr.id) > 0 {
                Button { model.markRead(pr) } label: { Label("\(snapshot.unreadCount(for: pr.id))", systemImage: "bubble.left.fill") }
                    .help("Новые комментарии. Нажмите, чтобы отметить прочитанными.")
            }
            Button { model.setHidden(pr, hidden: !hidden) } label: { Image(systemName: hidden ? "eye" : "eye.slash") }
                .help(hidden ? "Вернуть в основной список" : "Скрыть в More")
                .accessibilityLabel(hidden ? "Вернуть PR \(pr.number)" : "Скрыть PR \(pr.number)")
        }.padding(.vertical, 5)
    }
}
