import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var manager: PRManager

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
        .frame(width: 360, height: 380)
    }
}
