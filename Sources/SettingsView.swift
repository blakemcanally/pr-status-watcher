import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var manager: PRManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

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

                // Review Filters Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review Filters")
                        .font(.headline)

                    Text("Hide PRs on the Reviews tab that aren't ready for your review.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Hide draft PRs", isOn: filterBinding(\.hideDrafts))
                        Toggle("Hide PRs with failing CI", isOn: filterBinding(\.hideCIFailing))
                        Toggle("Hide PRs with pending CI", isOn: filterBinding(\.hideCIPending))
                        Toggle("Hide PRs with merge conflicts", isOn: filterBinding(\.hideConflicting))
                        Toggle("Hide already-approved PRs", isOn: filterBinding(\.hideApproved))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Review filter toggles")
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
}
