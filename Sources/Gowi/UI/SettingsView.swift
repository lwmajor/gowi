import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }

            RepositoriesPane()
                .tabItem { Label("Repositories", systemImage: "folder") }

            AccountPane()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .frame(width: 520, height: 360)
        .padding()
    }
}
