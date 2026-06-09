import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: ShelfPreferences

    let isLaunchAtLoginEnabled: () -> Bool
    let setLaunchAtLoginEnabled: (Bool) throws -> Void
    let loadStorageMetrics: () throws -> ShelfStorageMetrics
    let cleanNow: () throws -> ShelfCleanupResult

    @State private var launchAtLoginEnabled = false
    @State private var metrics: ShelfStorageMetrics?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Preferences")
                .font(.system(size: 20, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)

                Divider()

                Picker("Storage retention", selection: retentionBinding) {
                    ForEach(ShelfRetentionOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                if preferences.retentionOption == .custom {
                    Stepper(value: customRetentionBinding, in: ShelfPreferences.minimumCustomRetentionDays...ShelfPreferences.maximumCustomRetentionDays) {
                        Text("\(preferences.customRetentionDays) day(s)")
                    }
                    .padding(.leading, 2)
                }

                Picker("Storage size limit", selection: sizeLimitBinding) {
                    ForEach(ShelfSizeLimitOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                if preferences.sizeLimitOption == .custom {
                    Stepper(value: customSizeLimitBinding, in: ShelfPreferences.minimumCustomSizeLimitMB...ShelfPreferences.maximumCustomSizeLimitMB) {
                        Text("\(preferences.customSizeLimitMB) MB")
                    }
                    .padding(.leading, 2)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Stored items", value: itemCountText)
                LabeledContent("Total size", value: totalSizeText)
            }

            HStack {
                Button {
                    refreshMetrics()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Spacer()

                Button {
                    runCleanup()
                } label: {
                    Label("Clean Now", systemImage: "trash")
                }
                .keyboardShortcut(.defaultAction)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            launchAtLoginEnabled = isLaunchAtLoginEnabled()
            refreshMetrics()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLoginEnabled
        } set: { enabled in
            do {
                try setLaunchAtLoginEnabled(enabled)
                launchAtLoginEnabled = isLaunchAtLoginEnabled()
                statusMessage = enabled ? "Launch at Login enabled." : "Launch at Login disabled."
                errorMessage = nil
            } catch {
                launchAtLoginEnabled = isLaunchAtLoginEnabled()
                statusMessage = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private var retentionBinding: Binding<ShelfRetentionOption> {
        Binding {
            preferences.retentionOption
        } set: { option in
            preferences.retentionOption = option
        }
    }

    private var customRetentionBinding: Binding<Int> {
        Binding {
            preferences.customRetentionDays
        } set: { days in
            preferences.customRetentionDays = days
        }
    }

    private var sizeLimitBinding: Binding<ShelfSizeLimitOption> {
        Binding {
            preferences.sizeLimitOption
        } set: { option in
            preferences.sizeLimitOption = option
        }
    }

    private var customSizeLimitBinding: Binding<Int> {
        Binding {
            preferences.customSizeLimitMB
        } set: { megabytes in
            preferences.customSizeLimitMB = megabytes
        }
    }

    private var itemCountText: String {
        guard let metrics else { return "-" }
        return "\(metrics.itemCount)"
    }

    private var totalSizeText: String {
        guard let metrics else { return "-" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: metrics.totalBytes)
    }

    private func refreshMetrics() {
        do {
            metrics = try loadStorageMetrics()
            errorMessage = nil
        } catch {
            metrics = nil
            errorMessage = error.localizedDescription
        }
    }

    private func runCleanup() {
        do {
            let result = try cleanNow()
            refreshMetrics()
            if result.removedItemIDs.isEmpty {
                statusMessage = "No shelf items matched the cleanup policy."
            } else {
                statusMessage = "Removed \(result.removedItemIDs.count) item(s) and reclaimed \(formatBytes(result.reclaimedBytes))."
            }
            errorMessage = nil
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
