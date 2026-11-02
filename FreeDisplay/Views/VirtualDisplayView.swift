import SwiftUI
import CoreGraphics

/// "Virtual Displays" management section shown in the MenuBarView tools area.
/// Lists all saved virtual display configurations and allows creating / deleting them.
struct VirtualDisplayView: View {
    @StateObject private var service = VirtualDisplayService.shared
    @State private var showCreateForm = false
    @State private var configToDelete: UUID?
    @State private var isCreating: Bool = false
    @State private var createError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if service.configs.isEmpty {
                Text("No virtual displays")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(service.configs) { config in
                    VirtualDisplayConfigRow(config: config, service: service, configToDelete: $configToDelete)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
            }

            // "+" create button
            Button(action: { showCreateForm.toggle() }) {
                HStack {
                    Image(systemName: showCreateForm ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(showCreateForm ? String(localized: "Cancel") : String(localized: "Create Virtual Display"))
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .help("Create a new virtual display")

            if let err = createError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            if showCreateForm {
                CreateVirtualDisplayForm(isCreating: $isCreating, onConfirm: { config in
                    isCreating = true
                    createError = nil
                    Task { @MainActor in
                        let success = await service.addAndCreate(config)
                        isCreating = false
                        if success {
                            showCreateForm = false
                        } else {
                            createError = String(localized: "Couldn’t create the virtual display. Please try again.")
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                createError = nil
                            }
                        }
                    }
                })
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .alert("Confirm Delete", isPresented: Binding(
            get: { configToDelete != nil },
            set: { if !$0 { configToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = configToDelete {
                    service.removeConfig(id: id)
                }
                configToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                configToDelete = nil
            }
        } message: {
            if let id = configToDelete, service.isActive(id) {
                Text("This virtual display is active and will be turned off as soon as it’s deleted.")
            } else {
                Text("Delete this virtual display configuration?")
            }
        }
    }
}

// MARK: - Config Row

/// One saved virtual display: name, size, Active badge, Turn On/Off and Delete.
private struct VirtualDisplayConfigRow: View {
    let config: VirtualDisplayService.VirtualDisplayConfig
    @ObservedObject var service: VirtualDisplayService
    @Binding var configToDelete: UUID?
    @State private var isStarting = false
    @State private var startFailed = false

    var body: some View {
        let active = service.isActive(config.id)

        HStack(spacing: 8) {
            Image(systemName: "display.2")
                .foregroundColor(active ? .blue : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(config.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(config.width)×\(config.height)\(config.hiDPI ? " · HiDPI" : "") · \(Int(config.refreshRate))Hz")
                    .font(.caption2)
                    .foregroundColor(startFailed ? .red : .secondary)
            }

            Spacer()

            // Active / inactive badge
            if active {
                Text("Active")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)
            }

            // Turn a saved display on or off without deleting it
            Button(action: toggle) {
                if isStarting {
                    ProgressView().controlSize(.small)
                } else {
                    Label(active ? String(localized: "Turn Off") : String(localized: "Turn On"),
                          systemImage: active ? "stop.circle" : "play.circle")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .disabled(isStarting)
            .help(active ? "Turn off this virtual display" : "Turn on this virtual display")

            // Delete button
            Button(action: {
                configToDelete = config.id
            }) {
                Label("Delete", systemImage: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Delete this virtual display")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.08))
        )
        .contextMenu {
            Button(role: .destructive) {
                configToDelete = config.id
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func toggle() {
        if service.isActive(config.id) {
            service.destroy(configID: config.id)
            return
        }
        isStarting = true
        startFailed = false
        Task { @MainActor in
            startFailed = !(await service.start(configID: config.id))
            isStarting = false
        }
    }
}

// MARK: - Create Form

/// Inline form for creating a new virtual display configuration.
struct CreateVirtualDisplayForm: View {
    @Binding var isCreating: Bool
    let onConfirm: (VirtualDisplayService.VirtualDisplayConfig) -> Void

    @State private var name: String = String(localized: "Virtual Display")
    @State private var selectedPreset: Int = 0
    @State private var hiDPI: Bool = true
    @State private var autoCreate: Bool = true

    private let presets: [(label: String, width: Int, height: Int)] = [
        ("1920×1080 (FHD)", 1920, 1080),
        ("2560×1440 (QHD)", 2560, 1440),
        ("3840×2160 (4K)",  3840, 2160),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name field
            HStack {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                TextField("Display Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            // Resolution preset picker
            HStack {
                Text("Resolution")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                Picker("", selection: $selectedPreset) {
                    ForEach(presets.indices, id: \.self) { i in
                        Text(presets[i].label).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .labelsHidden()
                .help("Choose the virtual display’s resolution")
            }

            // HiDPI toggle
            HStack {
                Text("HiDPI")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                Toggle("", isOn: $hiDPI)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .help("Turn on high-resolution (Retina) mode")
                Text("Enable HiDPI Scaling")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Auto-create toggle
            HStack {
                Text("Auto")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                Toggle("", isOn: $autoCreate)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                Text("Create Automatically at Launch")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Confirm button
            Button(action: confirm) {
                HStack(spacing: 6) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    }
                    Text(isCreating ? String(localized: "Creating…") : String(localized: "Create"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isCreating)
        }
        .padding(.vertical, 4)
    }

    private func confirm() {
        guard !isCreating else { return }
        let preset = presets[selectedPreset]
        let config = VirtualDisplayService.VirtualDisplayConfig(
            name: name.isEmpty ? String(localized: "Virtual Display") : name,
            width: preset.width,
            height: preset.height,
            refreshRate: 60,
            hiDPI: hiDPI,
            autoCreate: autoCreate
        )
        onConfirm(config)
    }
}
