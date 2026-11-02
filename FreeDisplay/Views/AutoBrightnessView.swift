import SwiftUI

/// "Auto Brightness" section — follows builtin screen brightness and adjusts external display brightness automatically.
struct AutoBrightnessView: View {
    @StateObject private var service = AutoBrightnessService.shared
    @State private var isHovered = false

    /// True only after the service has polled at least once and found no builtin display.
    private var builtinUnavailable: Bool {
        service.hasPolled && service.builtinBrightness <= 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main toggle
            HStack {
                MenuItemIcon(systemName: "sun.max.trianglebadge.exclamationmark", color: service.isEnabled ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Brightness")
                        .font(.body)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $service.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    // Never lock the switch while it's on, or it can't be turned off.
                    .disabled(builtinUnavailable && !service.isEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(isHovered ? 0.06 : 0))
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())
        }
    }

    private var statusText: String {
        if builtinUnavailable {
            return String(localized: "No built-in display detected")
        } else if service.isEnabled {
            return String(localized: "Following built-in display brightness")
        } else {
            return String(localized: "Adjust external displays to follow the built-in display")
        }
    }
}
