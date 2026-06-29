//
//  StacksListView.swift
//  ContainerManager
//

import AppKit
import SwiftUI

struct StacksListView: View {
    @Binding var selection: String?
    @Environment(StacksStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var presentedSheet: StackCreateKind?
    @State private var deleteCandidate: String?

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(store.stacks) { stack in
                StackRow(stack: stack)
                    .tag(stack.name)
                    .contextMenu { rowMenu(stack) }
            }
        }
        .contextMenu { createMenu }
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
        .navigationTitle("Stacks")
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
            "Delete the stack “\(deleteCandidate ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                if let name = deleteCandidate { Task { await store.delete(name: name) } }
                deleteCandidate = nil
            }
        } message: {
            Text("Removes all of the stack's containers and its network. Data volumes are kept.")
        }
        .errorAlert($store.lastError)
        .onAppear(perform: consumeCreate)
        .onChange(of: router.pendingCreate) { consumeCreate() }
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }

    @ViewBuilder
    private func rowMenu(_ stack: Stack) -> some View {
        if !stack.allRunning {
            Button("Start") { Task { await store.start(name: stack.name) } }
        }
        if stack.anyRunning {
            Button("Stop") { Task { await store.stop(name: stack.name) } }
        }
        if let url = stack.webURL {
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button("Delete…", role: .destructive) { deleteCandidate = stack.name }
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
