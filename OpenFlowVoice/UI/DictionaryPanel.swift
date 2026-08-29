import AppKit
import SwiftUI

struct DictionaryPanel: View {
    @State private var store = DictionaryStore.shared
    @State private var query = ""
    @State private var editing: DictionaryEntry?
    @State private var isAdding = false

    private var entries: [DictionaryEntry] { store.filtered(by: query) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if entries.isEmpty {
                EmptyPanel(
                    label: store.entries.isEmpty ? "Dictionary empty" : "No matches",
                    detail: store.entries.isEmpty
                        ? "Add words it keeps getting wrong."
                        : "Try a different search."
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        DictionaryRow(
                            entry: entry,
                            onEdit: { editing = entry },
                            onToggle: {
                                var updated = entry
                                updated.isEnabled.toggle()
                                store.update(updated)
                            },
                            onDelete: { withAnimation { store.delete(entry) } }
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                footer
            }
        }
        .sheet(isPresented: $isAdding) {
            DictionaryEditor(entry: nil) { store.add($0) }
        }
        .sheet(item: $editing) { entry in
            DictionaryEditor(entry: entry) { store.update($0) }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField("Search dictionary", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().frame(height: 16)

            Button {
                isAdding = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help("New entry (⌘N)")
        }
        .background(.background.secondary)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var footer: some View {
        HStack {
            Text("\(store.entries.count) entr\(store.entries.count == 1 ? "y" : "ies")")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
            } label: {
                Text("Reveal dictionary.txt")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(DictionaryStore.fileURL.path)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Row

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                kindBadge

                if entry.kind == .correction {
                    HStack(spacing: 6) {
                        Text(entry.hear)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                        Text(entry.write)
                            .font(.body.weight(.medium))
                    }
                } else {
                    Text(entry.write)
                        .font(.body)
                }

                Spacer()

                if isHovering {
                    HStack(spacing: 4) {
                        dictActionPill("Edit", icon: "pencil") { onEdit() }
                        dictActionPill(entry.isEnabled ? "Disable" : "Enable",
                                      icon: entry.isEnabled ? "eye.slash" : "eye") { onToggle() }
                        dictActionPill("Delete", icon: "trash", isDestructive: true) { onDelete() }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
                }

                Circle()
                    .fill(entry.isEnabled ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .opacity(entry.isEnabled ? 1 : 0.5)

            Divider()
        }
        .background(isHovering ? Color.primary.opacity(0.03) : Color.clear)
        .animation(.easeInOut(duration: 0.1), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var kindBadge: some View {
        let isCorrection = entry.kind == .correction
        return Text(isCorrection ? "Fix" : "Term")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isCorrection ? Color.orange : Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                (isCorrection ? Color.orange : Color.accentColor).opacity(0.12),
                in: .capsule
            )
    }

    private func dictActionPill(
        _ label: String,
        icon: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isDestructive ? Color.red.opacity(0.75) : Color.primary)
            .glassEffect(in: .capsule)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Editor

private struct DictionaryEditor: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: DictionaryEntry.Kind
    @State private var hear: String
    @State private var write: String

    init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _kind = State(initialValue: entry?.kind ?? .term)
        _hear = State(initialValue: entry?.hear ?? "")
        _write = State(initialValue: entry?.write ?? "")
    }

    private var draft: DictionaryEntry {
        DictionaryEntry(
            id: entry?.id ?? UUID(),
            kind: kind,
            write: write.trimmingCharacters(in: .whitespacesAndNewlines),
            hear: kind == .correction ? hear.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            isEnabled: entry?.isEnabled ?? true
        )
    }

    private var warnings: [DictionaryWarning] { DictionaryWarning.check(draft) }

    private var isValid: Bool {
        !draft.write.isEmpty && (kind == .term || !draft.hear.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(entry == nil ? "New Entry" : "Edit Entry")
                .font(.title2.weight(.semibold))

            Picker("Kind", selection: Binding(
                get: { kind },
                set: { newKind in withAnimation(.easeInOut(duration: 0.18)) { kind = newKind } }
            )) {
                Text("Term").tag(DictionaryEntry.Kind.term)
                Text("Correction").tag(DictionaryEntry.Kind.correction)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 14) {
                if kind == .correction {
                    editorField("When the engine hears", text: $hear, prompt: "cloud code")
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                editorField(
                    kind == .correction ? "Write instead" : "Word or phrase",
                    text: $write,
                    prompt: kind == .correction ? "Claude Code" : "Anthropic"
                )
            }

            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(warnings) { warning in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .padding(.top, 1)
                            Text(warning.message)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
                )
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    guard isValid else { return }
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func editorField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.background.secondary, in: .rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
}
