import ServiceManagement
import SwiftUI

private enum SLAUnit: String, CaseIterable {
    case minutes = "Minutes"
    case hours = "Hours"
}

struct SettingsView: View {
    @EnvironmentObject var manager: PRManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var newCheckName = ""
    @State private var newIgnoredCheckName = ""
    @State private var newIgnoredRepo = ""
    @State private var slaUnit: SLAUnit = .hours

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

                // Review Readiness Section (general)
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.Readiness.settingsTitle)
                        .font(.headline)

                    Toggle("Hide draft PRs", isOn: filterBinding(\.hideDrafts))
                    Toggle("Hide PRs I've approved", isOn: filterBinding(\.hideApprovedByMe))
                    Toggle("Hide \"Not Ready\" PRs", isOn: filterBinding(\.hideNotReady))
                }

                Divider()

                // Review SLA Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.SLA.settingsTitle)
                        .font(.headline)

                    Text(Strings.SLA.settingsDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(Strings.SLA.enableToggle, isOn: filterBinding(\.reviewSLAEnabled))

                    if manager.filterSettings.reviewSLAEnabled {
                        HStack(spacing: 8) {
                            Text(Strings.SLA.deadlineLabel)
                                .font(.caption)

                            TextField("", value: slaValueBinding, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)

                            Picker("", selection: $slaUnit) {
                                ForEach(SLAUnit.allCases, id: \.self) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                    }
                }
                .onAppear {
                    let minutes = manager.filterSettings.reviewSLAMinutes
                    slaUnit = (minutes >= 60 && minutes % 60 == 0) ? .hours : .minutes
                }

                Divider()

                // Required CI Checks Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.Readiness.requiredChecksLabel)
                        .font(.headline)

                    Text(Strings.Readiness.settingsDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                                            .foregroundStyle(.secondary)
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
                        .accessibilityLabel("Add required check name")
                    }

                    // Autocomplete suggestions (excluding ignored checks)
                    let requiredSuggestions = requiredCheckNameSuggestions
                    if !requiredSuggestions.isEmpty && !newCheckName.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(requiredSuggestions, id: \.self) { suggestion in
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

                Divider()

                // Ignored CI Checks Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.Readiness.ignoredChecksLabel)
                        .font(.headline)

                    Text(Strings.Readiness.ignoredChecksDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Current ignored checks list
                    if !manager.filterSettings.ignoredCheckNames.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(manager.filterSettings.ignoredCheckNames, id: \.self) { name in
                                HStack {
                                    Text(name)
                                        .font(.system(.caption, design: .monospaced))
                                    Spacer()
                                    Button {
                                        manager.filterSettings.ignoredCheckNames.removeAll { $0 == name }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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

                    // Add new ignored check name
                    HStack(spacing: 6) {
                        TextField(Strings.Readiness.addIgnoredCheckPlaceholder, text: $newIgnoredCheckName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .onSubmit { addIgnoredCheck() }

                        Button {
                            addIgnoredCheck()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newIgnoredCheckName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add ignored check name")
                    }

                    // Autocomplete suggestions (excluding required checks)
                    let ignoredSuggestions = ignoredCheckNameSuggestions
                    if !ignoredSuggestions.isEmpty && !newIgnoredCheckName.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(ignoredSuggestions, id: \.self) { suggestion in
                                    Button(suggestion) {
                                        newIgnoredCheckName = suggestion
                                        addIgnoredCheck()
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
                }

                Divider()

                // Ignored Repositories Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.Repositories.ignoredReposLabel)
                        .font(.headline)

                    Text(Strings.Repositories.ignoredReposDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Current ignored repos list
                    if !manager.filterSettings.ignoredRepositories.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(manager.filterSettings.ignoredRepositories, id: \.self) { name in
                                HStack {
                                    Text(name)
                                        .font(.system(.caption, design: .monospaced))
                                    Spacer()
                                    Button {
                                        manager.filterSettings.ignoredRepositories.removeAll { $0 == name }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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

                    // Add new ignored repo
                    HStack(spacing: 6) {
                        TextField(Strings.Repositories.addIgnoredRepoPlaceholder, text: $newIgnoredRepo)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .onSubmit { addIgnoredRepo() }

                        Button {
                            addIgnoredRepo()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newIgnoredRepo.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add ignored repository")
                    }

                    // Autocomplete suggestions
                    let repoSuggestions = ignoredRepoSuggestions
                    if !repoSuggestions.isEmpty && !newIgnoredRepo.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(repoSuggestions, id: \.self) { suggestion in
                                    Button(suggestion) {
                                        newIgnoredRepo = suggestion
                                        addIgnoredRepo()
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

                    Text(Strings.Repositories.tipText)
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

    private var slaValueBinding: Binding<Int> {
        Binding(
            get: {
                let minutes = manager.filterSettings.reviewSLAMinutes
                switch slaUnit {
                case .minutes: return minutes
                case .hours: return minutes / 60
                }
            },
            set: { newValue in
                let clamped = max(1, newValue)
                switch slaUnit {
                case .minutes: manager.filterSettings.reviewSLAMinutes = clamped
                case .hours: manager.filterSettings.reviewSLAMinutes = clamped * 60
                }
            }
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
              !manager.filterSettings.requiredCheckNames.contains(trimmed),
              !manager.filterSettings.ignoredCheckNames.contains(trimmed) else { return }
        manager.filterSettings.requiredCheckNames.append(trimmed)
        newCheckName = ""
    }

    private func addIgnoredCheck() {
        let trimmed = newIgnoredCheckName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !manager.filterSettings.ignoredCheckNames.contains(trimmed),
              !manager.filterSettings.requiredCheckNames.contains(trimmed) else { return }
        manager.filterSettings.ignoredCheckNames.append(trimmed)
        newIgnoredCheckName = ""
    }

    /// Autocomplete for required checks: exclude names already required OR ignored.
    private var requiredCheckNameSuggestions: [String] {
        let excluded = Set(manager.filterSettings.requiredCheckNames)
            .union(manager.filterSettings.ignoredCheckNames)
        let query = newCheckName.lowercased()
        return manager.availableCheckNames
            .filter { !excluded.contains($0) && $0.lowercased().contains(query) }
    }

    /// Autocomplete for ignored checks: exclude names already ignored OR required.
    private var ignoredCheckNameSuggestions: [String] {
        let excluded = Set(manager.filterSettings.ignoredCheckNames)
            .union(manager.filterSettings.requiredCheckNames)
        let query = newIgnoredCheckName.lowercased()
        return manager.availableCheckNames
            .filter { !excluded.contains($0) && $0.lowercased().contains(query) }
    }

    // MARK: - Ignored Repositories Helpers

    private func addIgnoredRepo() {
        let trimmed = newIgnoredRepo.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !manager.filterSettings.ignoredRepositories.contains(trimmed) else { return }
        manager.filterSettings.ignoredRepositories.append(trimmed)
        newIgnoredRepo = ""
    }

    /// Autocomplete for ignored repos: exclude repos already in the ignore list.
    private var ignoredRepoSuggestions: [String] {
        let excluded = Set(manager.filterSettings.ignoredRepositories)
        let query = newIgnoredRepo.lowercased()
        return manager.availableRepositories
            .filter { !excluded.contains($0) && $0.lowercased().contains(query) }
    }
}
