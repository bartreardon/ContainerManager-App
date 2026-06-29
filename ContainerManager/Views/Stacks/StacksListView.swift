//
//  StacksListView.swift
//  ContainerManager
//

import AppKit
import SwiftUI

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
            case .template(let id):
                if let template = StackTemplates.all.first(where: { $0.id == id }) {
                    TemplateStackSheet(template: template)
                }
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

    @ViewBuilder
    private var createMenu: some View {
        ForEach(StackTemplates.all) { template in
            Button {
                presentedSheet = .template(template.id)
            } label: {
                Label(template.name, systemImage: template.systemImage)
            }
        }
        Divider()
        Button {
            presentedSheet = .custom
        } label: {
            Label("Custom Stack…", systemImage: "slider.horizontal.3")
        }
    }
}

enum StackCreateKind: Identifiable {
    case template(String)
    case custom
    var id: String {
        switch self {
        case .template(let id): id
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
            VStack(alignment: .leading, spacing: 2) {
                Text(stack.name)
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
