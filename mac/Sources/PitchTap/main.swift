import Foundation
import SwiftUI

struct PitchTapApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image(active: model.enabled))
            if !model.menuBarLabel.isEmpty { Text(model.menuBarLabel) }
        }
        .menuBarExtraStyle(.window)
    }
}

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
} else if let i = CommandLine.arguments.firstIndex(of: "--probe") {
    Probe.run(arguments: Array(CommandLine.arguments[i...]))
} else {
    PitchTapApp.main()
}
