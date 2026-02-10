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

                if let user = manager.ghUser {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Signed in as **\(user)**")
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not authenticated")
                                .font(.body.weight(.medium))
                            Text("Run this command in your terminal:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("gh auth login")
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(8)
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
        .frame(width: 360, height: 380)
    }
}
