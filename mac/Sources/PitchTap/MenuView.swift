import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $model.enabled) {
                Text("Pitch shift").font(.headline)
            }
            .toggleStyle(.switch)

            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Source", selection: $model.source) {
                Text(AudioSource.system.name).tag(AudioSource.system)
                Divider()
                ForEach(appOptions, id: \.source) { option in
                    Text(option.label).tag(option.source)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 6) {
                LabeledValue(title: "Semitones", value: String(format: "%+d", model.params.semitones))
                Slider(value: intBinding(\.semitones), in: -12...12, step: 1)
                LabeledValue(title: "Fine tune", value: String(format: "%+d cents", model.params.cents))
                Slider(value: intBinding(\.cents), in: -50...50, step: 1)
            }

            Divider()

            Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin },
                                                    set: { model.setLaunchesAtLogin($0) }))
            if let error = model.loginItemError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Reset") { model.reset() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            Text("⌃⌥↑ / ⌃⌥↓ semitone · ⌃⌥0 reset · PitchTap \(model.version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 290)
        .onAppear { model.refreshApps() }
        .onReceive(refresh) { _ in model.refreshApps() }
    }

    /// Apps known to Core Audio right now (♪ = playing), plus the selected app even if it isn't running.
    private var appOptions: [(label: String, source: AudioSource)] {
        var options = model.apps.map { (label: $0.isPlaying ? "\($0.name)  ♪" : $0.name, source: $0.source) }
        if case let .app(bundleID, name) = model.source, !model.apps.contains(where: { $0.bundleID == bundleID }) {
            options.append((label: "\(name) (not running)", source: model.source))
        }
        return options
    }

    private func intBinding(_ keyPath: WritableKeyPath<PitchParams, Int>) -> Binding<Double> {
        Binding(
            get: { Double(model.params[keyPath: keyPath]) },
            set: { model.params[keyPath: keyPath] = Int($0.rounded()) }
        )
    }
}

private struct LabeledValue: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
