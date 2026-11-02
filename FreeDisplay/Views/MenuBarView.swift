import SwiftUI

// MARK: - Shared Icon Helper

/// A colored rounded-square SF Symbol icon, consistent with macOS Settings style.
struct MenuItemIcon: View {
    let systemName: String
    var color: Color = .blue

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(color))
    }
}

// MARK: - ExpandableRow

struct ExpandableRow: View {
    let icon: String
    var iconColor: Color = .blue
    let label: String
    var subtitle: String? = nil
    @Binding var isExpanded: Bool
    @State private var isHovered = false

    var body: some View {
        HStack {
            MenuItemIcon(systemName: icon, color: iconColor)
            Text(label).font(.body)
            Spacer()
            if let sub = subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel(isExpanded ? String(localized: "\(label), expanded") : String(localized: "\(label), collapsed"))
        .accessibilityHint("Click to expand or collapse this section")
        .accessibilityAddTraits(.isButton)
        .help("Click to expand or collapse this section")
    }
}

/// Reports the natural height of the menu's scrollable content.
private struct MenuContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Warns that the brightness keys can't control external displays and links to the fix.
private struct BrightnessKeyPermissionBanner: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                Text("Brightness keys need Accessibility access")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            Text("Turn on FreeDisplay under Privacy & Security → Accessibility. If it's already on, remove it with – and add it again.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var displayManager: DisplayManager
    @ObservedObject private var updateService = UpdateService.shared
    @ObservedObject private var settings = SettingsService.shared
    @ObservedObject private var virtualDisplayService = VirtualDisplayService.shared
    @ObservedObject private var brightnessKeys = BrightnessKeyService.shared
    @State private var expandedDisplayIDs: Set<CGDirectDisplayID> = []
    @State private var showArrangement: Bool = false
    @State private var showVirtualDisplays: Bool = false
    @State private var showAutoBrightness: Bool = false
    @State private var showSettings: Bool = false
    @State private var quitHovered = false
    @State private var contentHeight: CGFloat = 0

    private static let maxScrollHeight: CGFloat = 640

    /// Scroll targets placed at the end of sections that expand near the bottom of the menu.
    private enum ScrollAnchor: Hashable {
        case virtualDisplays, autoBrightness, settings
    }

    private var visibleDisplays: [DisplayInfo] {
        displayManager.displays.filter { !virtualDisplayService.isVirtualDisplay($0.displayID) }
    }

    var body: some View {
        VStack(spacing: 0) {
        ScrollViewReader { scrollProxy in
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Brightness keys can't reach external displays without Accessibility.
                if !brightnessKeys.isActive && visibleDisplays.contains(where: { !$0.isBuiltin }) {
                    BrightnessKeyPermissionBanner { brightnessKeys.requestAccessibility() }
                }

                // Display list
                ForEach(visibleDisplays) { display in
                    VStack(spacing: 0) {
                        DisplayRowView(
                            display: display,
                            isExpanded: expandedDisplayIDs.contains(display.displayID),
                            onToggleExpand: {
                                if expandedDisplayIDs.contains(display.displayID) {
                                    expandedDisplayIDs.remove(display.displayID)
                                } else {
                                    expandedDisplayIDs.insert(display.displayID)
                                }
                            }
                        )

                        if expandedDisplayIDs.contains(display.displayID) {
                            DisplayDetailView(display: display)
                        }
                    }
                }

                // Preset list (Phase 19)
                Divider()
                    .opacity(0.3)
                    .padding(.vertical, 2)

                PresetListView()

                // Arrange Displays section (Phase 4)
                if visibleDisplays.count > 1 {
                    Divider()
                        .opacity(0.3)
                        .padding(.vertical, 2)

                    ExpandableRow(
                        icon: "rectangle.3.offgrid",
                        iconColor: .blue,
                        label: String(localized: "Arrange Displays"),
                        isExpanded: $showArrangement
                    )

                    if showArrangement {
                        ArrangementView()
                            .environmentObject(displayManager)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Divider()
                    .opacity(0.3)
                    .padding(.vertical, 2)

                // Combined brightness control (Phase 2)
                if settings.showCombinedBrightness {
                    CombinedBrightnessView(displays: displayManager.displays)
                    Divider()
                        .opacity(0.3)
                        .padding(.vertical, 2)
                }

                // Tools section header
                Text("Tools")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                // Virtual Displays tool entry (Phase 10)
                ExpandableRow(
                    icon: "display.2",
                    iconColor: .blue,
                    label: String(localized: "Virtual Displays"),
                    isExpanded: $showVirtualDisplays
                )

                if showVirtualDisplays {
                    VirtualDisplayView()
                        .padding(.leading, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Color.clear.frame(height: 0).id(ScrollAnchor.virtualDisplays)

                // Auto Brightness entry (Phase 11)
                ExpandableRow(
                    icon: "sun.and.horizon.fill",
                    iconColor: .orange,
                    label: String(localized: "Auto Brightness"),
                    isExpanded: $showAutoBrightness
                )

                if showAutoBrightness {
                    AutoBrightnessView()
                        .padding(.leading, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Color.clear.frame(height: 0).id(ScrollAnchor.autoBrightness)

                Divider()
                    .opacity(0.3)
                    .padding(.vertical, 2)

                // Settings section (Phase 12)
                ExpandableRow(
                    icon: "gearshape.fill",
                    iconColor: .gray,
                    label: String(localized: "Settings"),
                    isExpanded: $showSettings
                )

                if showSettings {
                    SettingsView()
                        .padding(.leading, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Color.clear.frame(height: 0).id(ScrollAnchor.settings)

                Divider()
                    .opacity(0.3)
                    .padding(.vertical, 2)

                // Update notice (Phase 12)
                if updateService.hasUpdate, let ver = updateService.latestVersion {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text("Version \(ver) available")
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                        Button("View") { updateService.openReleasePage() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .help("Download and install the latest version")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(6)
                    .padding(.horizontal, 8)
                }

            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: MenuContentHeightKey.self, value: geo.size.height)
                }
            )
        }
        // A ScrollView has no ideal height of its own, so the MenuBarExtra window
        // collapses it to zero. Size it to its content, capped so long menus scroll.
        .frame(height: min(contentHeight, Self.maxScrollHeight))
        .onPreferenceChange(MenuContentHeightKey.self) { contentHeight = $0 }
        // Expanding a section near the bottom adds rows below the visible area once the
        // menu reaches its height cap; scroll so the whole section shows.
        .onChange(of: showVirtualDisplays) { _, expanded in
            if expanded { reveal(.virtualDisplays, with: scrollProxy) }
        }
        .onChange(of: showAutoBrightness) { _, expanded in
            if expanded { reveal(.autoBrightness, with: scrollProxy) }
        }
        .onChange(of: showSettings) { _, expanded in
            if expanded { reveal(.settings, with: scrollProxy) }
        }
        } // end ScrollViewReader

        Divider().opacity(0.3)

        // Version and Quit (pinned to the bottom, doesn't scroll with the content)
        HStack {
            Text("FreeDisplay v\(updateService.currentVersion)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "xmark")
                        .accessibilityHidden(true)
                    Text("Quit")
                }
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(quitHovered ? Color.primary.opacity(0.06) : .clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(quitHovered ? .red : .secondary)
            .onHover { quitHovered = $0 }
            .help("Quit FreeDisplay")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)

        } // end VStack
        .frame(width: 340)
        .frame(maxHeight: 700)
        .padding(.vertical, 8)
        .onReceive(displayManager.$displays) { newDisplays in
            let validIDs = Set(newDisplays.map { $0.displayID })
            expandedDisplayIDs = expandedDisplayIDs.intersection(validIDs)
        }
        .task {
            if settings.checkUpdatesOnLaunch {
                await updateService.checkForUpdates()
            }
        }
    }
}

extension MenuBarView {
    /// Scrolls so the end of a just-expanded section is visible. Waits briefly so the new
    /// rows are laid out and the menu window has finished growing before scrolling.
    private func reveal(_ anchor: ScrollAnchor, with proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(anchor, anchor: .bottom)
            }
        }
    }
}

// MARK: - SettingsView (Phase 12: embedded in MenuBarView)

struct SettingsView: View {
    @ObservedObject private var settings = SettingsService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Launch at login
            Toggle(isOn: Binding(
                get: { settings.launchAtLogin },
                set: { newValue in
                    if newValue {
                        LaunchService.shared.enable()
                    } else {
                        LaunchService.shared.disable()
                    }
                    // Show what actually happened: register() can fail or need approval.
                    settings.launchAtLogin = LaunchService.shared.isEnabled
                    if newValue && LaunchService.shared.needsApproval {
                        LaunchService.shared.openLoginItemsSettings()
                    }
                }
            )) {
                HStack(spacing: 6) {
                    MenuItemIcon(systemName: "power", color: .green)
                        .accessibilityHidden(true)
                    Text("Launch at Login")
                        .font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .help("Start FreeDisplay automatically when you log in")

            // First-launch hint: recommend turning on Launch at Login
            if !settings.launchAtLoginPrompted {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text("Turning on Launch at Login is recommended")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Got It") {
                        settings.launchAtLoginPrompted = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .onAppear {
                    // Mark as prompted so it only shows once
                    // User dismisses manually via "Got It" button
                }
            }

            // Show combined brightness
            Toggle(isOn: $settings.showCombinedBrightness) {
                HStack(spacing: 6) {
                    MenuItemIcon(systemName: "sun.min.fill", color: .yellow)
                        .accessibilityHidden(true)
                    Text("Show Combined Brightness")
                        .font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .help("Show one brightness slider for all displays in the menu")

            // Check for updates at launch
            Toggle(isOn: $settings.checkUpdatesOnLaunch) {
                HStack(spacing: 6) {
                    MenuItemIcon(systemName: "arrow.clockwise.circle", color: .blue)
                        .accessibilityHidden(true)
                    Text("Check for Updates at Launch")
                        .font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .help("Check for a new version every time the app starts")

            CheckForUpdatesRow()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - CheckForUpdatesRow

/// "Check for Updates" button with the result of the last check underneath.
private struct CheckForUpdatesRow: View {
    @ObservedObject private var updateService = UpdateService.shared
    @State private var isHovered = false
    /// Only show "up to date" / errors after the user asked, not after the quiet launch check.
    @State private var didCheckManually = false

    var body: some View {
        HStack(spacing: 6) {
            MenuItemIcon(systemName: "arrow.down.circle", color: .blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Check for Updates")
                    .font(.body)
                if let status = statusText {
                    Text(status)
                        .font(.caption2)
                        .foregroundColor(updateService.hasUpdate ? .green
                                         : (updateService.lastCheckFailed ? .red : .secondary))
                }
            }
            Spacer()
            if updateService.isChecking {
                ProgressView().controlSize(.small)
            } else if updateService.hasUpdate {
                Button("Download") { updateService.openReleasePage() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Open the release page to download the new version")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0))
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !updateService.isChecking else { return }
            didCheckManually = true
            Task { await updateService.checkForUpdates(force: true) }
        }
        .accessibilityAddTraits(.isButton)
        .help("Check GitHub for a newer version of FreeDisplay")
    }

    private var statusText: String? {
        if updateService.isChecking { return String(localized: "Checking…") }
        if updateService.hasUpdate, let latest = updateService.latestVersion {
            return String(localized: "Version \(latest) is available")
        }
        guard didCheckManually else { return nil }
        if updateService.lastCheckFailed { return String(localized: "Couldn’t check for updates. Try again later.") }
        return String(localized: "FreeDisplay \(updateService.currentVersion) is up to date")
    }
}

// MARK: - DisplayRowView

struct DisplayRowView: View {
    @ObservedObject var display: DisplayInfo
    @EnvironmentObject var displayManager: DisplayManager
    @State private var isHovered: Bool = false

    let isExpanded: Bool
    let onToggleExpand: () -> Void

    private var rowAccessibilityLabel: String {
        String(localized: "Display: \(display.name)")
            + (display.isMain ? String(localized: ", main display") : "")
            + (isExpanded ? String(localized: ", expanded") : String(localized: ", collapsed"))
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                    .rotationEffect(Angle(degrees: isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    .accessibilityHidden(true)

                MenuItemIcon(systemName: display.isBuiltin ? "laptopcomputer" : "display", color: .blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let mode = display.currentDisplayMode {
                        Text(mode.resolutionString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                if display.isMain {
                    Text("Main")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(3)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }
            .help("Show display controls")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0))
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in System Settings", systemImage: "display")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(display.name, forType: .string)
            } label: {
                Label("Copy Display Name", systemImage: "doc.on.doc")
            }
        }
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityHint("Click to show the control panel")
        .accessibilityAddTraits(.isButton)
    }
}
