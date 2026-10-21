import AppIntents

struct RefreshPRIntent: AppIntent {
    static var title: LocalizedStringResource = "Обновить GitHub PR"
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        AppModel.shared.refresh()
        #endif
        return .result()
    }
}
