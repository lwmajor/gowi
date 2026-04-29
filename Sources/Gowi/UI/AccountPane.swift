import SwiftUI

struct AccountPane: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        VStack(spacing: 16) {
            if let viewer = model.viewer {
                AsyncImage(url: viewer.avatarUrl) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.secondary.opacity(0.2))
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())

                Text("@\(viewer.login)")
                    .font(.title3).bold()
                    .textSelection(.enabled)
            } else if auth.state == .signedIn {
                ProgressView("Loading account…")
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Not signed in")
                        .font(.headline)
                }
            }

            if let err = model.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if auth.state == .signedIn {
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
