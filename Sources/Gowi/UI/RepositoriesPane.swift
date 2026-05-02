import SwiftUI

struct RepositoriesPane: View {
    @EnvironmentObject private var store: RepoStore
    @EnvironmentObject private var model: AppModel
    @State private var showingAdd = false
    @State private var selectedRepo: TrackedRepo.ID?
    @State private var repoToDelete: TrackedRepo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.repos.isEmpty {
                emptyState
            } else {
                List(selection: $selectedRepo) {
                    ForEach(store.repos) { repo in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(repo.nameWithOwner)
                            Spacer()
                        }
                        .tag(repo.id)
                    }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(minHeight: 180)
                .onChange(of: store.repos) { _, repos in
                    if let id = selectedRepo, !repos.contains(where: { $0.id == id }) {
                        selectedRepo = nil
                    }
                }
            }

            HStack(spacing: 4) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add repository")

                Button {
                    confirmDelete(id: selectedRepo)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedRepo == nil)
                .help("Remove selected repository")

                Spacer()
                Text("\(store.repos.count) tracked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Intercepts Backspace/Delete key when a row is selected.
            Button("") { confirmDelete(id: selectedRepo) }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selectedRepo == nil)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .padding()
        .sheet(isPresented: $showingAdd) {
            AddRepoSheet()
                .environmentObject(store)
                .environmentObject(model)
        }
        .alert(
            "Remove \(repoToDelete?.nameWithOwner ?? "")?",
            isPresented: Binding(get: { repoToDelete != nil }, set: { if !$0 { repoToDelete = nil } })
        ) {
            Button("Remove", role: .destructive) {
                if let repo = repoToDelete { store.remove(repo) }
                repoToDelete = nil
            }
            Button("Cancel", role: .cancel) { repoToDelete = nil }
        } message: {
            Text("This repository will stop being tracked.")
        }
    }

    private func confirmDelete(id: TrackedRepo.ID?) {
        guard let id, let repo = store.repos.first(where: { $0.id == id }) else { return }
        repoToDelete = repo
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No repositories tracked yet")
                .font(.headline)
            Text("Add a repo as owner/name (e.g. apple/swift).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

private struct AddRepoSheet: View {
    @EnvironmentObject private var store: RepoStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var error: String?
    @State private var isValidating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add repository")
                .font(.headline)

            TextField("owner/name", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await perform() } }
                .disabled(isValidating)

            if let e = error {
                Text(e)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isValidating {
                    ProgressView().controlSize(.small)
                    Text("Checking with GitHub…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { Task { await perform() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isValidating || input.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

    @MainActor
    private func perform() async {
        error = nil
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard let repo = TrackedRepo(nameWithOwner: trimmed) else {
            error = "Enter the repo as owner/name (letters, numbers, dots, dashes, underscores)."
            return
        }
        if store.repos.contains(repo) {
            error = "\(repo.nameWithOwner) is already tracked."
            return
        }
        isValidating = true
        defer { isValidating = false }
        do {
            try await model.github.validateRepo(repo)
            store.add(repo)
            dismiss()
        } catch let e as GitHubError {
            self.error = e.errorDescription
        } catch let e {
            self.error = e.localizedDescription
        }
    }
}
