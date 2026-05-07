import AppKit
import SwiftUI

struct RepositoriesPane: View {
    private let actionMessageDuration: Duration = .seconds(2)

    @EnvironmentObject private var store: RepoStore
    @EnvironmentObject private var model: AppModel
    @State private var showingAdd = false
    @State private var selectedRepo: TrackedRepo.ID?
    @State private var repoToDelete: TrackedRepo?
    @State private var actionMessage: String?
    @State private var actionMessageToken = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.repos.isEmpty {
                emptyState
            } else {
                List(selection: $selectedRepo) {
                    ForEach(store.repos) { repo in
                        HStack {
                            NotifyToggle(repo: repo)
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
                Button("Export Repositories") {
                    exportRepos()
                }
                .disabled(store.repos.isEmpty)
                .help("Export repositories to the clipboard")
                .accessibilityIdentifier("exportReposButton")

                Button("Import Repositories") {
                    importRepos()
                }
                .help("Import repositories from the clipboard")
                .accessibilityIdentifier("importReposButton")

                Text("\(store.repos.count) repositories tracked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement()
                    .accessibilityLabel("Repository import or export status")
                    .accessibilityValue(actionMessage)
                    .accessibilityLiveRegion(.polite)
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

    private func exportRepos() {
        let text = store.exportText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showActionMessage("Copied!")
    }

    private func importRepos() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let result = store.importRepos(from: text)
        let skippedLabel = result.skipped == 1 ? "entry" : "entries"
        let skippedReason = "already tracked or invalid"
        if result.added == 0, result.skipped == 0 {
            showActionMessage("No repositories found to import.")
        } else if result.added == 0 {
            showActionMessage("No new repositories added. All \(result.skipped) \(skippedLabel) were \(skippedReason).")
        } else {
            showActionMessage("Added \(result.added) repositories, skipped \(result.skipped) \(skippedReason) \(skippedLabel).")
        }
    }

    private func showActionMessage(_ message: String) {
        let token = UUID()
        actionMessageToken = token
        actionMessage = message

        Task { @MainActor in
            try? await Task.sleep(for: actionMessageDuration)
            guard actionMessageToken == token else { return }
            actionMessage = nil
        }
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

private struct NotifyToggle: View {
    @EnvironmentObject private var notifications: NotificationService
    let repo: TrackedRepo

    var body: some View {
        let isOn = Binding<Bool>(
            get: { notifications.isEnabled(repo) },
            set: { newValue in
                Task { await notifications.setEnabled(newValue, for: repo) }
            }
        )
        Toggle(isOn: isOn) {
            Image(systemName: notifications.isEnabled(repo) ? "bell.fill" : "bell.slash")
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .help(notifications.isEnabled(repo) ? "Notifications on for this repo" : "Notify on new PRs")
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
