import AppIntents
import WidgetKit

struct ShowPRPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Показать список PR"
    @Parameter(title: "Скрытые") var hidden: Bool
    @Parameter(title: "Страница") var page: Int
    init() {}
    init(hidden: Bool, page: Int) { self.hidden = hidden; self.page = page }
    func perform() async throws -> some IntentResult {
        try SharedStore.open().setPresentation(hidden: hidden, page: page)
        return .result()
    }
}
struct HidePRIntent: AppIntent {
    static var title: LocalizedStringResource = "Скрыть или вернуть PR"
    @Parameter(title: "Аккаунт") var account: String
    @Parameter(title: "PR") var prID: String
    @Parameter(title: "Скрыть") var hidden: Bool
    init() {}
    init(account: String, prID: String, hidden: Bool) { self.account = account; self.prID = prID; self.hidden = hidden }
    func perform() async throws -> some IntentResult {
        try SharedStore.open().setHidden(account: account, prID: prID, hidden: hidden)
        return .result()
    }
}
struct ReadPRIntent: AppIntent {
    static var title: LocalizedStringResource = "Отметить PR прочитанным"
    @Parameter(title: "Аккаунт") var account: String
    @Parameter(title: "PR") var prID: String
    @Parameter(title: "Показанные комментарии") var commentIDs: [String]
    init() {}
    init(account: String, prID: String, commentIDs: [String]) {
        self.account = account; self.prID = prID; self.commentIDs = commentIDs
    }
    func perform() async throws -> some IntentResult {
        try SharedStore.open().markRead(account: account, prID: prID, displayedCommentIDs: Set(commentIDs))
        return .result()
    }
}
