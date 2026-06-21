import AppKit
import SwiftUI
import Perception

#if DEBUG
import DebugTools
#endif

@main
struct PerceptionLabApp: App {
    var body: some Scene {
        WindowGroup("Perception Lab") {
            #if DEBUG
            PerceptionLabView()
                .frame(minWidth: 1080, minHeight: 700)
            #else
            Text("Perception Lab is only available in Debug builds.")
                .frame(minWidth: 520, minHeight: 220)
            #endif
        }
    }
}

#if DEBUG
@MainActor
private final class PerceptionLabModel: ObservableObject {
    @Published var selectedKind: MockScenarioKind = .busyTyping
    @Published var scenario: ReplayScenario
    @Published var result: ReplayResult?
    @Published var selectedEventID: String?
    @Published var exportPath: String?
    @Published var errorMessage: String?
    @Published var debugFlags: PerceptionFeatureFlags
    @Published var liveResult: LivePerceptionTickResult?
    @Published var liveResults: [LivePerceptionTickResult] = []
    @Published var liveEvents: [PerceptionDiagnosticEvent] = []
    @Published var isRunningLiveTick = false
    @Published var isWatchingLive = false
    @Published var liveWatchTickCount = 0
    @Published var liveWatchBusySkips = 0
    @Published var liveWatchMessage = "idle"

    private let factory = MockScenarioFactory()
    private let writer = FixtureWriter()
    private let settings = PerceptionLabSettings()
    private let liveRunner = LivePerceptionRunner()
    private var liveWatchTask: Task<Void, Never>?

    init() {
        let initial = factory.make(.busyTyping)
        self.scenario = initial
        self.selectedEventID = initial.events.first?.id
        self.debugFlags = settings.loadFlags() ?? initial.events.first?.featureFlags ?? PerceptionFeatureFlags()
    }

    var selectedEvent: PerceptionDiagnosticEvent? {
        liveEvents.first { $0.id == selectedEventID }
            ?? scenario.events.first { $0.id == selectedEventID }
            ?? liveEvents.last
            ?? scenario.events.first
    }

    var selectedLiveResult: LivePerceptionTickResult? {
        liveResults.first { $0.event.id == selectedEventID } ?? liveResults.last
    }

    var recentEvents: [PerceptionDiagnosticEvent] {
        Array((liveEvents + scenario.events).suffix(12))
    }

    var recentLiveResults: [LivePerceptionTickResult] {
        Array(liveResults.suffix(20))
    }

    func selectScenario(_ kind: MockScenarioKind) {
        selectedKind = kind
        scenario = factory.make(kind)
        result = nil
        selectedEventID = scenario.events.first?.id
        exportPath = nil
        errorMessage = nil
    }

    func runReplay() {
        let scenario = scenario
        let flags = debugFlags
        Task {
            let replay = await PerceptionReplayRunner().replay(
                scenario,
                config: PerceptionReplayConfig(overrideFeatureFlags: flags)
            )
            await MainActor.run {
                self.result = replay
            }
        }
    }

    func runLiveTick() {
        Task {
            await runLiveTick(source: .manual)
        }
    }

    func startLiveWatch() {
        guard isWatchingLive == false else {
            return
        }

        isWatchingLive = true
        liveWatchTickCount = 0
        liveWatchBusySkips = 0
        liveWatchMessage = "watching every 2s"
        liveWatchTask = Task { [weak self] in
            while Task.isCancelled == false {
                await self?.runLiveTick(source: .watch)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopLiveWatch() {
        liveWatchTask?.cancel()
        liveWatchTask = nil
        isWatchingLive = false
        liveWatchMessage = "stopped"
    }

    private func runLiveTick(source: LiveTickSource) async {
        guard isRunningLiveTick == false else {
            if source == .watch {
                liveWatchBusySkips += 1
                liveWatchMessage = "skipped: previous tick still running"
            }
            return
        }

        isRunningLiveTick = true
        errorMessage = nil
        if source == .watch {
            liveWatchMessage = "running tick \(liveWatchTickCount + 1)"
        }

        let flags = debugFlags
        let result = await liveRunner.runTick(featureFlags: flags)
        appendLiveResult(result, source: source)
        isRunningLiveTick = false
    }

    private func appendLiveResult(_ result: LivePerceptionTickResult, source: LiveTickSource) {
        liveResult = result
        liveResults.append(result)
        liveResults = Array(liveResults.suffix(40))
        liveEvents.append(result.event)
        liveEvents = Array(liveEvents.suffix(40))
        selectedEventID = result.event.id
        if source == .watch {
            liveWatchTickCount += 1
            liveWatchMessage = "\(result.captureSkipped ? "skipped" : "captured") / \(result.event.decision.kind.rawValue)"
        }
    }

    func resetFlagsToSelectedEvent() {
        guard let selectedEvent else {
            return
        }
        debugFlags = selectedEvent.featureFlags
        settings.save(flags: debugFlags)
        result = nil
    }

    func setFlag(_ keyPath: WritableKeyPath<PerceptionFeatureFlags, Bool>, to value: Bool) {
        debugFlags[keyPath: keyPath] = value
        settings.save(flags: debugFlags)
        result = nil
    }

    func exportJSONL() {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PerceptionLab", isDirectory: true)
            let fileURL = directory.appendingPathComponent("\(scenario.id).jsonl")
            try writer.write(scenario, to: fileURL)
            exportPath = fileURL.path
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    deinit {
        liveWatchTask?.cancel()
    }
}

private enum LiveTickSource {
    case manual
    case watch
}

private struct PerceptionLabSettings {
    private let key = "PerceptionLab.debugFlags"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadFlags() -> PerceptionFeatureFlags? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(PerceptionFeatureFlags.self, from: data)
    }

    func save(flags: PerceptionFeatureFlags) {
        guard let data = try? JSONEncoder().encode(flags) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

private extension MockScenarioKind {
    var displayName: String {
        switch self {
        case .busyTyping:
            return "Busy Typing"
        case .switchToChat:
            return "Switch To Chat"
        case .staticReading:
            return "Static Reading"
        case .coWatchingSports:
            return "Co-watching Sports"
        case .screenLocked:
            return "Screen Locked"
        case .streamFallback:
            return "Stream Fallback"
        }
    }
}

private struct PerceptionLabView: View {
    @StateObject private var model = PerceptionLabModel()
    private let scenarioKinds: [MockScenarioKind] = [
        .busyTyping,
        .switchToChat,
        .staticReading,
        .coWatchingSports,
        .screenLocked,
        .streamFallback
    ]

    var body: some View {
        NavigationSplitView {
            scenarioList
        } content: {
            eventList
        } detail: {
            detailView
        }
        .toolbar {
            Button(model.isWatchingLive ? "Stop Live Watch" : "Start Live Watch") {
                model.isWatchingLive ? model.stopLiveWatch() : model.startLiveWatch()
            }
            Button(model.isRunningLiveTick ? "Running Live Tick" : "Run Live Tick") {
                model.runLiveTick()
            }
            .disabled(model.isRunningLiveTick)
            Button("Run Replay") {
                model.runReplay()
            }
            Button("Export JSONL") {
                model.exportJSONL()
            }
        }
    }

    private var scenarioList: some View {
        List(scenarioKinds, id: \.rawValue) { (kind: MockScenarioKind) in
            Button {
                model.selectScenario(kind)
            } label: {
                HStack {
                    Text(kind.displayName)
                    Spacer()
                    if kind == model.selectedKind {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Scenarios")
    }

    private var eventList: some View {
        List(selection: $model.selectedEventID) {
            if model.liveEvents.isEmpty == false {
                Section("Live") {
                    ForEach(model.liveEvents, id: \.id) { event in
                        eventRow(event)
                    }
                }
            }
            Section(model.scenario.name) {
                ForEach(model.scenario.events, id: \.id) { event in
                    eventRow(event)
                }
            }
        }
        .navigationTitle(model.scenario.name)
    }

    private func eventRow(_ event: PerceptionDiagnosticEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.id)
                .font(.headline)
            Text("\(event.mode.rawValue) / \(event.decision.kind.rawValue)")
                .foregroundStyle(.secondary)
            Text(event.traceId)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var detailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FeatureFlagPanel(flags: model.debugFlags, setFlag: model.setFlag, reset: model.resetFlagsToSelectedEvent)

                if let result = model.result {
                    ReplaySummaryView(result: result)
                }
                LiveWatchPanel(
                    isWatching: model.isWatchingLive,
                    isRunning: model.isRunningLiveTick,
                    tickCount: model.liveWatchTickCount,
                    busySkips: model.liveWatchBusySkips,
                    message: model.liveWatchMessage,
                    start: model.startLiveWatch,
                    stop: model.stopLiveWatch,
                    runOnce: model.runLiveTick
                )
                if let liveResult = model.liveResult {
                    LiveTickView(result: liveResult)
                }
                LiveTickTimelineView(results: model.recentLiveResults, selectedEventID: $model.selectedEventID)
                if let liveResult = model.selectedLiveResult {
                    CapturedFramePreview(result: liveResult)
                }
                if let event = model.selectedEvent {
                    CurrentSnapshotView(event: event)
                    GateDecisionTimelineView(events: model.recentEvents, selectedEventID: $model.selectedEventID)
                    GateDecisionView(event: event)
                    PetActionPreviewView(event: event)
                }
                if let exportPath = model.exportPath {
                    Text("Exported: \(exportPath)")
                        .font(.footnote)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Frame Detail")
    }
}

private struct FeatureFlagPanel: View {
    var flags: PerceptionFeatureFlags
    var setFlag: (WritableKeyPath<PerceptionFeatureFlags, Bool>, Bool) -> Void
    var reset: () -> Void

    var body: some View {
        LabSection("Feature Flags") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                flagRow("singleFrameCapture", \.singleFrameCapture, "regionDHash", \.regionDHash)
                flagRow("multiSignalTrigger", \.multiSignalTrigger, "attentionStateMachine", \.attentionStateMachine)
                flagRow("screenStateMonitor", \.screenStateMonitor, "coWatchingStream", \.coWatchingStream)
                flagRow("keyframeExtraction", \.keyframeExtraction, "ocrRecognition", \.ocrRecognition)
                flagRow("systemAudioCapture", \.systemAudioCapture, "whisperTranscription", \.whisperTranscription)
                GridRow {
                    flagToggle("webMetadataSearch", \.webMetadataSearch)
                    Button("Reset To Event") {
                        reset()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func flagRow(
        _ left: String,
        _ leftPath: WritableKeyPath<PerceptionFeatureFlags, Bool>,
        _ right: String,
        _ rightPath: WritableKeyPath<PerceptionFeatureFlags, Bool>
    ) -> some View {
        GridRow {
            flagToggle(left, leftPath)
            flagToggle(right, rightPath)
        }
    }

    private func flagToggle(
        _ title: String,
        _ keyPath: WritableKeyPath<PerceptionFeatureFlags, Bool>
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { flags[keyPath: keyPath] },
                set: { setFlag(keyPath, $0) }
            )
        )
        .toggleStyle(.checkbox)
        .frame(width: 220, alignment: .leading)
    }
}

private struct LiveWatchPanel: View {
    var isWatching: Bool
    var isRunning: Bool
    var tickCount: Int
    var busySkips: Int
    var message: String
    var start: () -> Void
    var stop: () -> Void
    var runOnce: () -> Void

    var body: some View {
        LabSection("Live Watch") {
            HStack(spacing: 12) {
                Button(isWatching ? "Stop" : "Start") {
                    isWatching ? stop() : start()
                }
                .buttonStyle(.borderedProminent)
                Button(isRunning ? "Running" : "Run Once") {
                    runOnce()
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)
                statusPill(isWatching ? "watching / 2s" : "stopped", isWatching ? .green : .secondary)
                statusPill(message, isRunning ? .orange : .secondary)
            }
            HStack(spacing: 24) {
                metric("Ticks", tickCount)
                metric("Busy Skips", busySkips)
                metric("In Flight", isRunning ? 1 : 0)
            }
        }
    }

    private func statusPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(color)
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.monospacedDigit())
        }
        .frame(width: 104, alignment: .leading)
    }
}

private struct LiveTickView: View {
    var result: LivePerceptionTickResult

    var body: some View {
        LabSection("Live Tick") {
            LabLabeled("Screen", result.screenState.rawValue)
            LabLabeled("Front App", result.frontAppSnapshot.appName)
            LabLabeled("Windows", result.frontAppSnapshot.windowTitles.joined(separator: ", "))
            LabLabeled("Capture", result.captureSkipped ? "skipped" : "captured")
            if let frame = result.frame {
                LabLabeled("Frame", "\(frame.width)x\(frame.height) display=\(frame.displayID.map(String.init) ?? "unknown")")
            }
            if let battery = result.powerSnapshot.powerState.batteryLevel {
                LabLabeled("Battery", "\(Int((battery * 100).rounded()))%")
            } else {
                LabLabeled("Battery", "unknown")
            }
            LabLabeled("Charging", result.powerSnapshot.powerState.isCharging ? "true" : "false")
            LabLabeled("Low Power", result.powerSnapshot.powerState.isLowPowerMode ? "true" : "false")
            LabLabeled("Thermal", result.powerSnapshot.thermalState.rawValue)
            if let hash = result.event.snapshot?.regionHash {
                LabLabeled("Hash", "global \(hash.globalDistance), changed \(hash.changedRegions.map(\.rawValue).joined(separator: ", "))")
                RegionHashGridView(hash: hash)
            }
            if result.event.errors.isEmpty == false {
                LabLabeled("Errors", result.event.errors.map(errorSummary).joined(separator: "\n"))
            }
        }
    }

    private func errorSummary(_ error: DiagnosticErrorDTO) -> String {
        "\(error.module).\(error.code): \(error.message)"
    }
}

private struct LiveTickTimelineView: View {
    var results: [LivePerceptionTickResult]
    @Binding var selectedEventID: String?

    var body: some View {
        LabSection("Live Tick Timeline") {
            if results.isEmpty {
                Text("none")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results.reversed(), id: \.event.id) { result in
                        timelineRow(result)
                    }
                }
            }
        }
    }

    private func timelineRow(_ result: LivePerceptionTickResult) -> some View {
        let event = result.event
        let isSelected = event.id == selectedEventID
        return Button {
            selectedEventID = event.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(for: event.decision.kind, captured: result.captureSkipped == false))
                        .frame(width: 9, height: 9)
                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption.monospacedDigit())
                        .frame(width: 92, alignment: .leading)
                    Text(result.captureSkipped ? "skipped" : "captured")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(result.captureSkipped ? Color.secondary : Color.green)
                        .frame(width: 74, alignment: .leading)
                    Text(event.decision.kind.rawValue)
                        .font(.caption.weight(.semibold))
                        .frame(width: 118, alignment: .leading)
                    Text(result.frontAppSnapshot.appName)
                        .lineLimit(1)
                    Spacer()
                    Text("\(event.latency.totalMs ?? 0)ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(rowDetails(result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func rowDetails(_ result: LivePerceptionTickResult) -> String {
        let event = result.event
        var parts: [String] = []
        if result.frontAppSnapshot.windowTitles.isEmpty == false {
            parts.append("window: \(result.frontAppSnapshot.windowTitles.joined(separator: ", "))")
        }
        if let hash = event.snapshot?.regionHash {
            let changed = hash.changedRegions.map(\.rawValue).joined(separator: ", ")
            parts.append("hash: global \(hash.globalDistance), changed \(changed.isEmpty ? "none" : changed)")
        }
        if event.decision.reasons.isEmpty == false {
            parts.append("why: \(event.decision.reasons.joined(separator: ", "))")
        }
        if event.errors.isEmpty == false {
            parts.append("errors: \(event.errors.map { $0.code }.joined(separator: ", "))")
        }
        return parts.isEmpty ? "no details" : parts.joined(separator: " | ")
    }

    private func color(for kind: GateDecisionKind, captured: Bool) -> Color {
        if captured {
            return .green
        }
        switch kind {
        case .fallback:
            return .orange
        case .skipPrivacyBlocked, .pausedScreenLocked, .pausedScreenSleeping, .pausedSystemSleeping:
            return .red
        default:
            return .secondary
        }
    }
}

private struct CapturedFramePreview: View {
    var result: LivePerceptionTickResult
    @State private var savedPath: String?
    @State private var saveError: String?

    var body: some View {
        LabSection("Captured Screenshot") {
            if let frame = result.frame, let image = nsImage(from: frame) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 760, maxHeight: 420)
                    .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(frame.width)x\(frame.height)")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5))
                            .padding(8)
                    }
                HStack(spacing: 10) {
                    Button("Save PNG") {
                        save(frame: frame)
                    }
                    .buttonStyle(.bordered)
                    LabLabeled("Frame ID", frame.id)
                }
                if let savedPath {
                    LabLabeled("Saved", savedPath)
                }
                if let saveError {
                    Text(saveError)
                        .foregroundStyle(.red)
                }
            } else {
                Text(result.captureSkipped ? "No image: capture skipped" : "No decodable image data")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func nsImage(from frame: CapturedFrame) -> NSImage? {
        guard let imageData = frame.imageData else {
            return nil
        }
        return NSImage(data: imageData)
    }

    private func save(frame: CapturedFrame) {
        guard let imageData = frame.imageData else {
            saveError = "No image data to save."
            return
        }
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PerceptionLab", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(frame.id).png")
            try imageData.write(to: url, options: .atomic)
            savedPath = url.path
            saveError = nil
        } catch {
            savedPath = nil
            saveError = error.localizedDescription
        }
    }
}

private struct RegionHashGridView: View {
    var hash: RegionHashDTO
    private let rows: [[ScreenRegion]] = [
        [.topLeft, .topCenter, .topRight],
        [.middleLeft, .center, .middleRight],
        [.bottomLeft, .bottomCenter, .bottomRight]
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Changed Regions")
                .font(.caption)
                .foregroundStyle(.secondary)
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { region in
                            regionCell(region)
                        }
                    }
                }
            }
        }
    }

    private func regionCell(_ region: ScreenRegion) -> some View {
        let distance = hash.regionDistances[region] ?? 0
        let changed = hash.changedRegions.contains(region)
        return VStack(spacing: 2) {
            Text(shortName(region))
                .font(.caption2)
            Text("\(distance)")
                .font(.caption.monospacedDigit())
        }
        .frame(width: 86, height: 44)
        .background(changed ? Color.orange.opacity(0.22) : Color.secondary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(changed ? Color.orange : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func shortName(_ region: ScreenRegion) -> String {
        switch region {
        case .topLeft: return "top L"
        case .topCenter: return "top C"
        case .topRight: return "top R"
        case .middleLeft: return "mid L"
        case .center: return "center"
        case .middleRight: return "mid R"
        case .bottomLeft: return "bot L"
        case .bottomCenter: return "bot C"
        case .bottomRight: return "bot R"
        }
    }
}

private struct CurrentSnapshotView: View {
    var event: PerceptionDiagnosticEvent

    var body: some View {
        LabSection("Current Snapshot") {
            if let snapshot = event.snapshot {
                LabLabeled("App", snapshot.appName)
                LabLabeled("Windows", snapshot.windowTitles.joined(separator: ", "))
                LabLabeled("Idle", String(format: "%.1fs", snapshot.idleDuration))
                LabLabeled("Recent Input", snapshot.recentInputActive ? "active" : "inactive")
                LabLabeled("Attention", snapshot.attentionState.rawValue)
                LabLabeled("Content", snapshot.contentType?.rawValue ?? "unknown")
                if let screenshotRef = snapshot.screenshotRef {
                    LabLabeled("Screenshot", screenshotRef)
                }
                if let hash = snapshot.regionHash {
                    LabLabeled("Hash", "global \(hash.globalDistance), changed \(hash.changedRegions.map(\.rawValue).joined(separator: ", "))")
                }
            } else if let coWatching = event.coWatchingSnapshot {
                LabLabeled("App", coWatching.appName)
                LabLabeled("Windows", coWatching.windowTitles.joined(separator: ", "))
                LabLabeled("Content", coWatching.contentType.rawValue)
                LabLabeled("Keyframes", coWatching.keyframeRefs.joined(separator: ", "))
                LabLabeled("OCR", coWatching.ocrText.joined(separator: " / "))
                LabLabeled("Transcript", coWatching.audioTranscript ?? "none")
                LabLabeled("Summary", coWatching.recentSummary ?? "none")
            } else {
                Text("none")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GateDecisionTimelineView: View {
    var events: [PerceptionDiagnosticEvent]
    @Binding var selectedEventID: String?

    var body: some View {
        LabSection("Gate Decision Timeline") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(events, id: \.id) { event in
                    Button {
                        selectedEventID = event.id
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(color(for: event.decision.kind))
                                .frame(width: 8, height: 8)
                            Text(event.id)
                                .font(.system(.body, design: .monospaced))
                            Text(event.decision.kind.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(event.latency.totalMs ?? 0)ms")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .background(event.id == selectedEventID ? Color.accentColor.opacity(0.12) : Color.clear)
                }
            }
        }
    }

    private func color(for kind: GateDecisionKind) -> Color {
        switch kind {
        case .analyze:
            return .green
        case .fallback:
            return .orange
        case .skipPrivacyBlocked, .pausedScreenLocked, .pausedScreenSleeping, .pausedSystemSleeping:
            return .red
        default:
            return .secondary
        }
    }
}

private struct GateDecisionView: View {
    var event: PerceptionDiagnosticEvent

    var body: some View {
        LabSection("Gate Decision") {
            LabLabeled("Frame", event.id)
            LabLabeled("Trace", event.traceId)
            LabLabeled("Decision", event.decision.kind.rawValue)
            LabLabeled("Reasons", list(event.decision.reasons))
            LabLabeled("Signals", list(event.decision.triggeredSignals.map(\.rawValue)))
            LabLabeled("Fallbacks", event.decision.fallbacks.isEmpty ? "none" : list(event.decision.fallbacks))
            LabLabeled("Latency", latencySummary(event.latency))
            if event.errors.isEmpty == false {
                LabLabeled("Errors", list(event.errors.map(errorSummary)))
            }
        }
    }

    private func list(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: "\n")
    }

    private func latencySummary(_ latency: PerceptionLatency) -> String {
        var parts: [String] = []
        appendLatency("capture", latency.captureMs, to: &parts)
        appendLatency("hash", latency.hashMs, to: &parts)
        appendLatency("gate", latency.gateMs, to: &parts)
        appendLatency("ocr", latency.ocrMs, to: &parts)
        appendLatency("whisper", latency.whisperMs, to: &parts)
        appendLatency("keyframe", latency.keyframeMs, to: &parts)
        appendLatency("total", latency.totalMs, to: &parts)
        return parts.isEmpty ? "none" : parts.joined(separator: "\n")
    }

    private func appendLatency(_ name: String, _ value: Int?, to parts: inout [String]) {
        guard let value else {
            return
        }
        parts.append("\(name): \(value)ms")
    }

    private func errorSummary(_ error: DiagnosticErrorDTO) -> String {
        "\(error.module).\(error.code): \(error.message)"
    }
}

private struct PetActionPreviewView: View {
    var event: PerceptionDiagnosticEvent

    var body: some View {
        LabSection("PetAction Preview") {
            if event.petActions.isEmpty {
                LabLabeled("Expression", "none")
                LabLabeled("Animation", "none")
                LabLabeled("Bubble", "none")
                LabLabeled("Suppressed", "false")
                LabLabeled("Suppress Reason", "none")
            } else {
                ForEach(Array(event.petActions.enumerated()), id: \.offset) { index, action in
                    LabLabeled("Action \(index + 1)", action.type.rawValue)
                    LabLabeled("Payload", payload(action.payload))
                    if action.type == .suppressBubble {
                        LabLabeled("Suppressed", "true")
                        LabLabeled("Suppress Reason", action.payload["reason"] ?? "unknown")
                    }
                }
            }
        }
    }

    private func payload(_ payload: [String: String]) -> String {
        payload.isEmpty
            ? "none"
            : payload.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n")
    }
}

private struct ReplaySummaryView: View {
    var result: ReplayResult

    var body: some View {
        LabSection("Replay") {
            HStack(spacing: 16) {
                metric("Events", result.totalEvents)
                metric("Analyze", result.analyzedCount)
                metric("Skip", result.skippedCount)
                metric("Fallback", result.fallbackCount)
            }
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title2.monospacedDigit())
        }
        .frame(width: 92, alignment: .leading)
    }
}

private struct LabSection<Content: View>: View {
    var title: String
    var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }
}

private struct LabLabeled: View {
    var title: String
    var value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value.isEmpty ? "none" : value)
                .textSelection(.enabled)
        }
    }
}
#endif
