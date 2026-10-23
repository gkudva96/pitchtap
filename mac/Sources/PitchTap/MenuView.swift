import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: Updates
    @State private var fineTuneShown = false
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(spacing: 8) {
                sourceCard
                keyCard
                tuningCard
            }
            .opacity(model.enabled ? 1 : 0.5)

            footer
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { model.refreshApps() }
        .onReceive(refresh) { _ in model.refreshApps() }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(nsImage: MenuBarIcon.image(active: false))
                Text("PitchTap").font(.headline)
                Spacer()
                Toggle("Pitch shift", isOn: $model.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(model.statusText).fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var sourceCard: some View {
        Card(title: "Source") {
            HStack(spacing: 8) {
                SourceIcon(source: model.source)
                Picker("Source", selection: $model.source) {
                    Text(AudioSource.system.name).tag(AudioSource.system)
                    Divider()
                    ForEach(appOptions, id: \.source) { option in
                        Text(option.label).tag(option.source)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var keyCard: some View {
        Card(title: "Key") {
            VStack(spacing: 8) {
                HStack {
                    RoundButton(symbol: "minus", label: "Down a semitone") { model.nudge(by: -1) }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(signed(model.params.semitones))
                            .font(.system(size: 38, weight: .semibold))
                            .monospacedDigit()
                        if model.params.cents != 0 {
                            Text(signed(model.params.cents) + "¢").font(.callout).foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .opacity(hearingOriginal ? 0.45 : 1)
                    Spacer()
                    RoundButton(symbol: "plus", label: "Up a semitone") { model.nudge(by: 1) }
                }

                HStack(spacing: 4) {
                    Text(hearingOriginal ? "Playing the original key" : model.params.musicalDescription)
                    if !hearingOriginal, let hint = model.params.fretHint { FretHintButton(hint: hint) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Slider(value: intBinding(\.semitones), in: -12...12, step: 1)
                    .labelsHidden()

                Picker("Listen to", selection: $model.hearingOriginal) {
                    Text("Original").tag(true)
                    Text("Shifted").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!model.enabled)
            }
        } accessory: {
            if !model.params.isNeutral {
                Button { model.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reset to the original key")
                    .accessibilityLabel("Reset to the original key")
            }
        }
    }

    private var tuningCard: some View {
        Card(title: nil) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Tuning").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .leading)
                    Picker("Tuning", selection: $model.params.cents) {
                        ForEach(PitchParams.tunings, id: \.cents) { Text($0.name).tag($0.cents) }
                        if !PitchParams.tunings.contains(where: { $0.cents == model.params.cents }) {
                            Text(String(format: "Custom (%+d cents)", model.params.cents)).tag(model.params.cents)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                Button { withAnimation(.easeOut(duration: 0.15)) { fineTuneShown.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(fineTuneShown ? 90 : 0))
                        Text("Fine tune")
                        Spacer()
                        Text(signed(model.params.cents) + " cents").monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityValue(fineTuneShown ? "Shown" : "Hidden")
                if fineTuneShown {
                    Slider(value: intBinding(\.cents), in: -50...50, step: 1).labelsHidden()
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PitchTap \(model.version)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin },
                                                            set: { model.setLaunchesAtLogin($0) }))
                    Button("Check for Updates…") { updates.check() }
                        .disabled(!updates.canCheck)
                    // Real items, so macOS draws them enabled with the shortcut right-aligned (these work from
                    // any app via HotKeys; here they're also clickable).
                    Menu("Keyboard Shortcuts") {
                        Button("Semitone Up") { model.nudge(by: 1) }
                            .keyboardShortcut(.upArrow, modifiers: [.control, .option])
                        Button("Semitone Down") { model.nudge(by: -1) }
                            .keyboardShortcut(.downArrow, modifiers: [.control, .option])
                        Button("Original / Shifted") { model.hearingOriginal.toggle() }
                            .keyboardShortcut("b", modifiers: [.control, .option])
                            .disabled(!model.enabled)
                        Button("Reset Key") { model.reset() }
                            .keyboardShortcut("0", modifiers: [.control, .option])
                    }
                    Button("Show Welcome") { Welcome.show() }
                    Divider()
                    Button("Quit PitchTap") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Settings")
            }
            if let error = model.loginItemError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Helpers

    private var hearingOriginal: Bool { model.enabled && model.hearingOriginal }

    private var statusColor: Color {
        switch model.status {
        case .off: return .gray
        case .active: return .green
        case .waiting, .silent: return .orange
        case .failed: return .red
        }
    }

    /// Apps known to Core Audio right now (♪ = playing), plus the selected app even if it isn't running.
    private var appOptions: [(label: String, source: AudioSource)] {
        var options = model.apps.map { (label: $0.isPlaying ? "\($0.name)  ♪" : $0.name, source: $0.source) }
        if case let .app(bundleID, name) = model.source, !model.apps.contains(where: { $0.bundleID == bundleID }) {
            options.append((label: "\(name) (not running)", source: model.source))
        }
        return options
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : value < 0 ? "−\(-value)" : "0"
    }

    private func intBinding(_ keyPath: WritableKeyPath<PitchParams, Int>) -> Binding<Double> {
        Binding(
            get: { Double(model.params[keyPath: keyPath]) },
            set: { model.params[keyPath: keyPath] = Int($0.rounded()) }
        )
    }
}

/// A rounded group with an optional small heading and a trailing accessory (e.g. reset).
private struct Card<Content: View, Accessory: View>: View {
    let title: String?
    @ViewBuilder let content: Content
    @ViewBuilder let accessory: Accessory

    init(title: String?, @ViewBuilder content: () -> Content,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    accessory
                }
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct RoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The selected app's own icon, or a speaker for all system audio.
private struct SourceIcon: View {
    let source: AudioSource

    var body: some View {
        Group {
            if case let .app(bundleID, _) = source,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.gray, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// ⓘ that opens the capo / retuning hint. A click, not a tooltip: menu-bar panels aren't the active
/// app, so tooltips don't show.
private struct FretHintButton: View {
    let hint: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.plain)
            .accessibilityLabel("Fretted instrument hint")
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(hint)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 240, alignment: .leading)
                    .padding(12)
            }
    }
}
