import AppKit
import SwiftUI

/// First-launch window. PitchTap has no window or Dock icon, so without this a new user opens it
/// and sees nothing happen.
enum Welcome {
    private static let shownKey = "welcomeShown"
    private static var window: NSWindow?

    static func showIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return }
        UserDefaults.standard.set(true, forKey: shownKey)
        show()
    }

    static func show() {
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered,
                                  defer: false)
            window.title = "Welcome to PitchTap"
            window.isReleasedWhenClosed = false
            let content = NSHostingView(rootView: WelcomeView { [weak window] in window?.close() })
            window.contentView = content
            window.setContentSize(content.fittingSize)
            window.center()
            Self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PitchTap is in your menu bar").font(.title2.bold())
                    Text("Change the key of any song. Same tempo.").foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text("Look for this icon at the top-right of your screen:")
                Image(nsImage: MenuBarIcon.image(active: false))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 10) {
                Step(number: 1, text: "Click the icon to open the controls.")
                Step(number: 2, text: "Switch on **Pitch shift**, choose a **Source** such as Spotify, and move the "
                    + "**Semitones** slider.")
                Step(number: 3, text: "The first time, macOS asks to record system audio. Click **Allow**. PitchTap "
                    + "only changes the sound as it plays; nothing is recorded, saved or sent.")
            }

            Text("Shortcuts from any app: ⌃⌥↑ / ⌃⌥↓ change the key, ⌃⌥0 resets.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Got it", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.bold().monospacedDigit())
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            Text(.init(text)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
