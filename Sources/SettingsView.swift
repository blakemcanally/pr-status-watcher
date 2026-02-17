import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var manager: PRManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var newCheckName = ""

    private let intervalOptions: [(label: String, seconds: Int)] = [
        ("30 seconds", 30),
        ("1 minute", 60),
        ("90 seconds", 90),
        ("2 minutes", 120),
        ("5 minutes", 300)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("PR Status Watcher")
                    .font(.title2.weight(.semibold))

                Divider()

                // GitHub Auth Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("GitHub Authentication")
                        .font(.headline)

                    AuthStatusView(username: manager.ghUser, style: .detailed)
                }

                Divider()

                // Startup Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Startup")
                        .font(.headline)

                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .accessibilityHint("Automatically start the app when you log in")
                        .onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                                loginError = nil
                            } catch {
                                launchAtLogin = !newValue  // revert toggle
                                loginError = error.localizedDescription
                            }
                        }
                    if let loginError {
                        Text(loginError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Divider()

                // Polling Interval Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh Interval")
                        .font(.headline)

                    Text("How often to check GitHub for PR status updates.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Interval", selection: $manager.refreshInterval) {
                        ForEach(intervalOptions, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .accessibilityLabel("Refresh interval")
                }

                Divider()

                // Review Readiness Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.Readiness.settingsTitle)
                        .font(.headline)

                    Text(Strings.Readiness.settingsDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Hide draft PRs", isOn: filterBinding(\.hideDrafts))

                    // Current required checks list
                    if !manager.filterSettings.requiredCheckNames.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(manager.filterSettings.requiredCheckNames, id: \.self) { name in
                                HStack {
                                    Text(name)
                                        .font(.system(.caption, design: .monospaced))
                                    Spacer()
                                    Button {
                                        manager.filterSettings.requiredCheckNames.removeAll { $0 == name }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remove \(name)")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.08))
                                .cornerRadius(4)
                            }
                        }
                    }

                    // Add new check name
                    HStack(spacing: 6) {
                        checkNameTextField
                        Button {
                            addRequiredCheck()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newCheckName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add check name")
                    }

                    // Autocomplete suggestions
                    let suggestions = checkNameSuggestions
                    if !suggestions.isEmpty && !newCheckName.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button(suggestion) {
                                        newCheckName = suggestion
                                        addRequiredCheck()
                                    }
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(4)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Text(Strings.Readiness.tipText)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(24)
        }
        .frame(
            minWidth: AppConstants.Layout.SettingsWindow.minWidth,
            idealWidth: AppConstants.Layout.SettingsWindow.idealWidth,
            maxWidth: AppConstants.Layout.SettingsWindow.maxWidth,
            minHeight: AppConstants.Layout.SettingsWindow.minHeight,
            idealHeight: AppConstants.Layout.SettingsWindow.idealHeight,
            maxHeight: AppConstants.Layout.SettingsWindow.maxHeight
        )
    }

    private func filterBinding(_ keyPath: WritableKeyPath<FilterSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { manager.filterSettings[keyPath: keyPath] },
            set: { manager.filterSettings[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Required Checks Helpers

    private var checkNameTextField: some View {
        TextField(Strings.Readiness.addCheckPlaceholder, text: $newCheckName)
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
            .onSubmit { addRequiredCheck() }
    }

    private func addRequiredCheck() {
        let trimmed = newCheckName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !manager.filterSettings.requiredCheckNames.contains(trimmed) else { return }
        manager.filterSettings.requiredCheckNames.append(trimmed)
        newCheckName = ""
    }

    /// Autocomplete suggestions: check names seen in recent PRs that aren't already required,
    /// filtered by current text field input.
    private var checkNameSuggestions: [String] {
        let existing = Set(manager.filterSettings.requiredCheckNames)
        let query = newCheckName.lowercased()
        return manager.availableCheckNames
            .filter { !existing.contains($0) && $0.lowercased().contains(query) }
    }
}
