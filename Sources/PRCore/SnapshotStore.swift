import Foundation
import Darwin

public final class SnapshotStore: @unchecked Sendable {
    public let directory: URL
    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        let fd = open(directory.appendingPathComponent("state.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
    private func load() throws -> PRSnapshot {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return PRSnapshot() }
        let result = try JSONDecoder().decode(PRSnapshot.self, from: Data(contentsOf: stateURL))
        guard result.version == 1 else { throw CocoaError(.fileReadUnknown) }
        return result
    }
    public func read() throws -> PRSnapshot { try locked { try load() } }
    public func importIfMissing(from source: URL) throws {
        try locked {
            guard !FileManager.default.fileExists(atPath: stateURL.path) else { return }
            let data = try Data(contentsOf: source)
            let snapshot = try JSONDecoder().decode(PRSnapshot.self, from: data)
            guard snapshot.version == 1 else { throw CocoaError(.fileReadUnknown) }
            try data.write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        }
    }
    private func update(_ change: (inout PRSnapshot) -> Void) throws {
        try locked {
            var value = try load()
            change(&value)
            let data = try JSONEncoder().encode(value)
            try data.write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        }
    }
    public func applySync(account: String, pullRequests: [PullRequest], at: Date) throws {
        try update { state in
            let login = account.lowercased()
            if state.account != login { state.showHidden = false; state.pageIndex = 0 }
            state.account = login
            for pr in pullRequests where state.accounts[login]?[pr.id] == nil {
                var preferences = PRPreferences()
                preferences.readIDs = pr.commentIDs
                state.accounts[login, default: [:]][pr.id] = preferences
            }
            let latestCommits = Dictionary(grouping: pullRequests, by: \.repository)
                .mapValues { $0.compactMap(\.lastCommitAt).max() ?? .distantPast }
            state.pullRequests = pullRequests.sorted {
                if $0.repository == $1.repository { return $0.number > $1.number }
                let lhs = latestCommits[$0.repository]!, rhs = latestCommits[$1.repository]!
                return lhs == rhs ? $0.repository < $1.repository : lhs > rhs
            }
            state.lastSuccessAt = at; state.lastAttemptAt = at
            state.nextAttemptAt = at.addingTimeInterval(1800)
            state.isRefreshing = false; state.error = nil; state.rateLimitUntil = nil
        }
    }
    public func setHidden(account: String, prID: String, hidden: Bool) throws {
        try update { state in
            guard state.account == account, state.accounts[account]?[prID] != nil else { return }
            state.accounts[account]?[prID]?.hidden = hidden
        }
    }
    public func markRead(account: String, prID: String, displayedCommentIDs: Set<String>) throws {
        try update { state in
            guard state.account == account, state.accounts[account]?[prID] != nil else { return }
            state.accounts[account]?[prID]?.readIDs.formUnion(displayedCommentIDs)
        }
    }
    public func setPresentation(hidden: Bool, page: Int) throws {
        try update { $0.showHidden = hidden; $0.pageIndex = max(0, page) }
    }
    public func beginAttempt(at: Date) throws {
        try update { $0.isRefreshing = true; $0.lastAttemptAt = at; $0.error = nil }
    }
    public func failAttempt(message: String, at: Date, retryAfter: Date? = nil) throws {
        try update {
            $0.isRefreshing = false; $0.error = message; $0.lastAttemptAt = at
            $0.nextAttemptAt = max(at.addingTimeInterval(1800), retryAfter ?? at)
            $0.rateLimitUntil = retryAfter
        }
    }
    public func recoverInterruptedAttempt() throws {
        try update { if $0.isRefreshing { $0.isRefreshing = false; $0.error = "Предыдущее обновление прервано. Нажмите «Обновить»." } }
    }
}
