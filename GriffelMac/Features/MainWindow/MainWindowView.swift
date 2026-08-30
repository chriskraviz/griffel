import SwiftUI

/// The app's window: topic folders, the filed recordings, and the Braindump
/// inbox — all three visible at once on purpose. An import is a thought that
/// arrived as a file, and it usually wants to end up in the same place as a
/// spoken one.
///
/// The whole window is a drop destination, so a file can be released anywhere
/// over it; a drop on a folder row in the sidebar files it straight into that
/// topic.
struct MainWindowView: View {
    @Bindable var appState: AppState

    static let defaultSize = CGSize(width: 1180, height: 720)
    /// Wide enough for all three columns. Folder management lives in the
    /// sidebar, so a window that can be resized below the sidebar breakpoint
    /// would have a range where topics cannot be created, renamed or deleted
    /// at all — the minimum and the breakpoint are therefore the same number.
    static let minimumSize = CGSize(width: 1000, height: 540)

    private static let sidebarWidth: CGFloat = 200
    private static let braindumpPaneWidth: CGFloat = 380
    /// Matches `minimumSize.width`. The fold still exists for a display too
    /// small to honour the minimum, where AppKit clamps the window anyway.
    private static let sidebarBreakpoint: CGFloat = 1000

    @State private var filter = LibraryFilter()
    @State private var isDropTargeted = false
    @State private var rejectedFileNames: [String] = []
    @State private var isSidebarVisible = true

    var body: some View {
        VStack(spacing: 0) {
            header

            if let workflow = appState.activeWorkflow, workflow.phase.isActive {
                WindowActivityBar(workflow: workflow) {
                    appState.stopCurrentWorkflow()
                }
                Divider()
            }

            switch appState.windowSection {
            case .library:
                panes
            case .settings:
                WideSettingsView(appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .background(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)
            .allowsHitTesting(false)
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleImport(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.55), lineWidth: 2)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.14), value: isDropTargeted)
        .onAppear { appState.library.refresh() }
    }

    private var panes: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if isSidebarVisible {
                    LibrarySidebarView(appState: appState, filter: filter)
                        .frame(width: Self.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }

                LibraryListView(
                    appState: appState,
                    filter: filter,
                    isDropTargeted: isDropTargeted,
                    showsFolderMenu: !isSidebarVisible,
                    rejectedFileNames: $rejectedFileNames,
                    onImport: handleImport
                )
                .frame(maxWidth: .infinity)

                Divider()

                braindumpPane
                    .frame(width: Self.braindumpPaneWidth)
            }
            .onChange(of: geometry.size.width, initial: true) { _, width in
                let shouldShow = width >= Self.sidebarBreakpoint
                if shouldShow != isSidebarVisible {
                    withAnimation(.easeOut(duration: 0.16)) { isSidebarVisible = shouldShow }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Griffel")
                .font(.system(size: 12.5, weight: .semibold))

            GlassChip {
                Image(systemName: appState.appSettings.secureLocalModeEnabled ? "lock.shield.fill" : "network")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(appState.appSettings.secureLocalModeEnabled ? .green : .blue)
                Text(engineLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Only the modes still live over there. The settings used to be
            // named here as a signpost; a signpost in the place a control
            // belongs is a control that has not been built yet.
            if appState.windowSection == .library {
                Text("Modi liegen im Men\u{00FC}leisten-Symbol.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Button {
                appState.windowSection = appState.windowSection == .settings ? .library : .settings
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.windowSection == .settings ? "tray.full" : "gearshape")
                        .font(.system(size: 10, weight: .semibold))
                    Text(appState.windowSection == .settings ? "Ablage" : "Einstellungen")
                }
            }
            .buttonStyle(.vc(.quiet, .compact))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var engineLabel: String {
        appState.appSettings.secureLocalModeEnabled
            ? "Lokal \u{00B7} \(appState.selectedLocalModelDisplayName)"
            : "Online \u{00B7} Whisper"
    }

    // MARK: - Braindump Pane

    private var braindumpPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: WorkflowType.braindump.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WorkflowType.braindump.accentUIColor)

                Text("Braindump")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                let unprocessed = BraindumpStore.shared.unprocessedCount
                if unprocessed > 0 {
                    GlassChip {
                        Text("\(unprocessed) offen")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider() }

            BraindumpView(appState: appState, allowsFiling: true, filingFolderName: filter.scope.folderName)
        }
    }

    // MARK: - Import

    private func handleImport(_ urls: [URL]) {
        let rejected = appState.importAudioFiles(urls, intoFolder: filter.scope.folderName)
        rejectedFileNames = rejected.map(\.lastPathComponent)
    }
}

/// Live strip for whatever run is in flight, so a hotkey started elsewhere —
/// or the Braindump button in this window — reports back here instead of only
/// in the floating HUD.
struct WindowActivityBar: View {
    let workflow: any Workflow
    let onStop: () -> Void

    private var accent: Color { workflow.type.accentUIColor }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: workflow.type.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 16)

            Text(workflow.type.displayName)
                .font(.system(size: 11, weight: .semibold))

            if workflow.isRecording {
                WaveformView(
                    audioLevel: workflow.audioLevel,
                    isRecording: true,
                    accentColor: accent,
                    barWidth: 3,
                    minBarHeight: 3
                )
                .frame(height: 18)
                .frame(maxWidth: 180)
            }

            Text(phaseText)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if workflow.isRecording {
                Button("Stopp") { onStop() }
                    .buttonStyle(.vc(.secondary, .compact, tint: accent))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(accent.opacity(0.07))
    }

    private var phaseText: String {
        switch workflow.phase {
        case .idle: return ""
        case .running(let message): return message
        case .done: return "Fertig."
        case .error(let message): return message
        }
    }
}
