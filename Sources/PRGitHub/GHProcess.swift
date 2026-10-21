import Foundation

public struct GHProcess: GHExecuting {
    private let executable: URL?
    private let timeout: TimeInterval
    public init(executable: URL? = nil, timeout: TimeInterval = 90) {
        self.executable = executable; self.timeout = timeout
    }
    public func run(arguments: [String]) async throws -> Data {
        try await Task.detached(priority: .utility) { try runBlocking(arguments: arguments) }.value
    }
    private func runBlocking(arguments: [String]) throws -> Data {
        let paths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/gh" }
        guard let url = executable ?? paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:)) else {
            throw FetchFailure("GitHub CLI не найден. Установите gh и выполните gh auth login.")
        }
        let process = Process()
        process.executableURL = url; process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        for key in ["GH_TOKEN", "GITHUB_TOKEN", "GH_HOST", "GH_DEBUG"] { environment.removeValue(forKey: key) }
        environment["GH_PROMPT_DISABLED"] = "1"; environment["GH_PAGER"] = "cat"
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors; process.standardInput = FileHandle.nullDevice
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        do { try process.run() } catch { throw FetchFailure("Не удалось запустить gh. Проверьте установку GitHub CLI.") }
        // Drain both streams concurrently so a full pipe cannot block process completion.
        let readers = DispatchGroup()
        let out = DataBox(), err = DataBox()
        readers.enter()
        DispatchQueue.global().async { out.value = output.fileHandleForReading.readDataToEndOfFile(); readers.leave() }
        readers.enter()
        DispatchQueue.global().async { err.value = errors.fileHandleForReading.readDataToEndOfFile(); readers.leave() }
        let timedOut = completed.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if completed.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        }
        readers.wait()
        if timedOut { throw FetchFailure("GitHub не ответил вовремя. Повторите обновление.") }
        guard process.terminationStatus == 0 else {
            let message = String(data: err.value, encoding: .utf8)?.lowercased() ?? ""
            if message.contains("rate limit") || message.contains("http 429") {
                throw FetchFailure("Достигнут лимит GitHub API. Повторная попытка через час.", retryAfter: Date().addingTimeInterval(3600))
            }
            if message.contains("auth login") || message.contains("http 401") || message.contains("bad credentials") {
                throw FetchFailure("Выполните gh auth login в Терминале, затем нажмите «Обновить».")
            }
            if message.contains("http 403") || message.contains("http 404") {
                throw FetchFailure("GitHub отказал в доступе к одному из репозиториев. Проверьте gh auth status и доступ SSO.")
            }
            throw FetchFailure("Не удалось получить данные GitHub. Проверьте подключение и gh auth status.")
        }
        return out.value
    }
    private final class DataBox: @unchecked Sendable { var value = Data() }
}
