import Foundation
import Darwin

enum SharedStore {
    static let widgetKind = "GitHubPRList"
    static func open() throws -> SnapshotStore {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else {
            throw CocoaError(.fileReadNoPermission)
        }
        // A local ad-hoc build cannot share a team-signed App Group on macOS 15.
        // The extension entitlement grants access to this app's state directory only.
        let directory = URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/GitHub PR/PRState", isDirectory: true)
        let store = try SnapshotStore(directory: directory)
        #if !WIDGET_EXTENSION
        let state = directory.appendingPathComponent("state.json")
        if !FileManager.default.fileExists(atPath: state.path),
           let legacy = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.local.GitHubPRWidget")?
            .appendingPathComponent("PRState/state.json"),
           FileManager.default.fileExists(atPath: legacy.path) {
            try store.importIfMissing(from: legacy)
        }
        #endif
        return store
    }
}
