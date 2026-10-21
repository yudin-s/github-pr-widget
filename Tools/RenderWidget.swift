import SwiftUI
import AppKit

// Renders the real SwiftUI widget view for layout inspection; does not emulate WidgetKit actions.
@main struct RenderWidget {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: render-widget state.json output.png") }
        let snapshot = try JSONDecoder().decode(PRSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let view = NSHostingView(rootView: PRWidgetView(snapshot: snapshot)
            .padding(16).frame(width: 360, height: 360)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
        view.frame = NSRect(x: 0, y: 0, width: 360, height: 360)
        view.appearance = NSAppearance(named: .aqua)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
