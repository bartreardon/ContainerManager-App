//
//  StacksListView.swift
//  ContainerManager
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StacksListView: View {
    @Binding var selection: Set<String>
    @Environment(StacksStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var presentedSheet: StackCreateKind?
    @State private var deleteCandidates: Set<String> = []
    @State private var searchText = ""

    private var stacks: [Stack] {
        guard !searchText.isEmpty else { return store.stacks }
        return store.stacks.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(stacks) { stack in
                StackRow(stack: stack)
                    .tag(stack.name)
                    .draggable(stack.name)
                    .copyable([stack.name])
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(ids)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter stacks")
        .overlay {
            if store.stacks.isEmpty {
                ContentUnavailableView {
                    Label("No Stacks", systemImage: "square.stack.3d.up")
                } description: {
                    Text("A stack wires up several containers together — like a web app and its database — in one step.")
                } actions: {
                    Menu("New Stack…") { createMenu }
                        .menuStyle(.borderedButton)
                        .fixedSize()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    createMenu
                } label: {
                    Label("New Stack", systemImage: "plus")
                }
                .help("Create a new stack")
            }
        }
        .sheet(item: $presentedSheet) { kind in
            switch kind {
            case .template(let template):
                TemplateStackSheet(template: template)
            case .custom:
                CustomStackSheet()
            }
        }
        .confirmationDialog(
            deleteCandidates.count > 1
                ? "Delete \(deleteCandidates.count) stacks?"
                : "Delete the stack “\(deleteCandidates.first ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                let names = deleteCandidates
                Task { for name in names { await store.delete(name: name) } }
                deleteCandidates = []
            }
        } message: {
            Text("Removes all of the stacks' containers and networks. Data volumes are kept.")
        }
        .errorAlert($store.lastError)
        .onAppear(perform: consumeCreate)
        .onChange(of: router.pendingCreate) { consumeCreate() }
        .onAppear(perform: consumeImport)
        .onChange(of: router.pendingStackImport) { consumeImport() }
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: AppDefaults.listRefresh)
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { !deleteCandidates.isEmpty }, set: { if !$0 { deleteCandidates = [] } })
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<String>) -> some View {
        if ids.isEmpty {
            createMenu
        } else {
            let stacks = ids.compactMap { store.stack(named: $0) }
            if stacks.contains(where: { !$0.allRunning }) {
                Button("Start") { Task { for name in ids { await store.start(name: name) } } }
            }
            if stacks.contains(where: { $0.anyRunning }) {
                Button("Stop") { Task { for name in ids { await store.stop(name: name) } } }
            }
            if ids.count == 1, let stack = stacks.first, let url = stack.webURL {
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
            }
            Button(ids.count > 1 ? "Copy Names" : "Copy Name") { Pasteboard.copy(ids.sorted()) }
            Divider()
            Button("Delete…", role: .destructive) { deleteCandidates = ids }
        }
    }

    private func consumeCreate() {
        if router.pendingCreate == .stacks {
            presentedSheet = .custom
            router.pendingCreate = nil
        }
    }

    /// Imports a definition file opened from Finder (routed via `onOpenURL`).
    private func consumeImport() {
        guard let url = router.pendingStackImport else { return }
        router.pendingStackImport = nil
        do {
            present(try StackTemplateLibrary.importFile(at: url))
        } catch {
            store.lastError = PresentedError(title: "Couldn’t import stack definition", error: error)
        }
    }

    @ViewBuilder
    private var createMenu: some View {
        ForEach(StackTemplates.all) { template in
            templateButton(template)
        }
        // Re-read on every menu open so edits in the Finder folder show immediately.
        let imported = StackTemplateLibrary.list()
        if !imported.isEmpty {
            Divider()
            ForEach(imported) { template in
                templateButton(template)
            }
        }
        Divider()
        Button {
            presentedSheet = .custom
        } label: {
            Label("Custom Stack…", systemImage: "slider.horizontal.3")
        }
        Divider()
        Button("Import Template…") { importTemplate() }
        Button("Show Templates Folder") { StackTemplateLibrary.reveal() }
    }

    private func templateButton(_ template: StackTemplateDef) -> some View {
        Button {
            presentedSheet = .template(template)
        } label: {
            Label(template.name, systemImage: template.systemImage)
        }
    }

    /// Imports a stack definition (native `.containerstack`/JSON, or a docker-compose
    /// YAML converted on the way in) and opens its create sheet.
    private func importTemplate() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.containerstack, .json, .yaml]
        panel.message = "Choose a stack definition (.containerstack) or a docker-compose file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            present(try StackTemplateLibrary.importFile(at: url))
        } catch {
            store.lastError = PresentedError(title: "Couldn’t import stack definition", error: error)
        }
    }

    /// Opens the imported template's create sheet, first surfacing any compose-import
    /// caveats (what didn't carry over) in an app-modal alert.
    private func present(_ template: StackTemplateDef) {
        if let document = template.document, let summary = ComposeImporter.caveats(in: document) {
            let alert = NSAlert()
            alert.messageText = ComposeImporter.hasLosses(summary) ? "Imported with caveats" : "Imported"
            alert.informativeText = summary
            alert.runModal()
        }
        presentedSheet = .template(template)
    }
}

enum StackCreateKind: Identifiable {
    case template(StackTemplateDef)
    case custom
    var id: String {
        switch self {
        case .template(let template): template.id
        case .custom: "custom"
        }
    }
}

struct StackRow: View {
    let stack: Stack

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stack.allRunning ? .green : (stack.anyRunning ? .orange : .secondary.opacity(0.5)))
                .frame(width: 9, height: 9)
            Image(systemName: stack.icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(stack.displayName)
                    .fontWeight(.medium)
                Text("\(stack.runningCount)/\(stack.services.count) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if stack.webURL != nil {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .help("Has a web endpoint")
            }
        }
        .padding(.vertical, 2)
    }
}
