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
            }

            Spacer()
        }
        .padding(24)
        .frame(
            minWidth: 320, idealWidth: 360, maxWidth: 480,
            minHeight: 380, idealHeight: 430, maxHeight: 600
        )
    }
}
