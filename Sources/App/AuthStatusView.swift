import SwiftUI

struct AuthStatusView: View {
    let username: String?
    let style: Style

    enum Style {
        case compact   // footer: icon + username only
        case detailed  // settings: full card with instructions
    }

    var body: some View {
        if let username {
            authenticatedView(username: username)
        } else {
            unauthenticatedView
        }
    }

    @ViewBuilder
    private func authenticatedView(username: String) -> some View {
        switch style {
        case .compact:
            HStack(spacing: 4) {
                Image(systemName: "person.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text(username)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel(Strings.Auth.signedIn(username))
        case .detailed:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Signed in as **\(username)**")
                Spacer()
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .cornerRadius(8)
            .accessibilityLabel(Strings.Auth.signedIn(username))
        }
    }

    @ViewBuilder
    private var unauthenticatedView: some View {
        switch style {
        case .compact:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text(Strings.Auth.compactNotAuth)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel(Strings.Auth.notAuthenticated)
        case .detailed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.Auth.notAuthenticated)
                        .font(.body.weight(.medium))
                    Text(Strings.Auth.authInstructions)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Strings.Auth.authCommand)
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
            .accessibilityLabel("\(Strings.Auth.notAuthenticated). \(Strings.Auth.authInstructions) \(Strings.Auth.authCommand)")
        }
    }
}
