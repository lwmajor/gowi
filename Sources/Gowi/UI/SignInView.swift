import SwiftUI
import AppKit

struct SignInView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var publicReposOnly = false

    var body: some View {
        Group {
            switch auth.state {
            case .signedOut:
                idle
            case .awaitingUserCode(let code):
                awaiting(code)
            case .failed(let message):
                failed(message)
            case .signedIn:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - sub-views

    private var idle: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sign in with GitHub")
                .font(.title2).bold()
            Text("gowi only reads pull requests. GitHub doesn't offer a read-only private-repo scope for OAuth apps — signing in with the full scope grants broader access than gowi uses.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
            Toggle("Public repos only (narrower scope)", isOn: $publicReposOnly)
                .toggleStyle(.checkbox)
            Button {
                auth.startSignIn(publicReposOnly: publicReposOnly)
            } label: {
                Text("Sign in with GitHub").frame(minWidth: 180)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
    }

    private func awaiting(_ code: DeviceCodeResponse) -> some View {
        VStack(spacing: 16) {
            Text("Enter this code on GitHub")
                .font(.headline)

            HStack(spacing: 8) {
                Text(code.userCode)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(code.userCode, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }

            Text("GitHub should already be open in your browser. If not:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.open(code.urlToOpen)
            } label: {
                Label("Open GitHub", systemImage: "safari")
            }

            ProgressView().controlSize(.small)

            Button("Cancel") { auth.cancelSignIn() }
                .buttonStyle(.link)
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Sign-in failed")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Try Again") { auth.cancelSignIn() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
