import SwiftUI
import SwiftData
import FocusCore

struct ScratchpadScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredScratchItem.order) private var items: [StoredScratchItem]
    @State private var newText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputBar
            Divider()
            list
        }
        .navigationTitle("Scratchpad")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear Checked", role: .destructive, action: clearChecked)
                    Button("Clear All", role: .destructive, action: clearAll)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(FocusColors.focusRed)
            TextField("Capture a thought or task…", text: $newText, axis: .horizontal)
                .focused($inputFocused)
                .submitLabel(.done)
                .onSubmit { add() }
            if !newText.isEmpty {
                Button("Add") { add() }
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(PadTheme.pad)
        .background(Color(.secondarySystemBackground))
    }

    private var list: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "Empty",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Dump distracting thoughts and tasks here while you focus.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        row(item)
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func row(_ item: StoredScratchItem) -> some View {
        HStack(spacing: 12) {
            Button {
                item.isChecked.toggle()
                try? context.save()
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isChecked ? FocusColors.goalGreen : .secondary)
            }
            Text(item.text)
                .strikethrough(item.isChecked)
                .foregroundStyle(item.isChecked ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                context.delete(item)
                try? context.save()
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func add() {
        let t = newText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let order = (items.map(\.order).max() ?? -1) + 1
        let item = StoredScratchItem()
        item.text = t
        item.order = order
        context.insert(item)
        try? context.save()
        newText = ""
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(items[i]) }
        try? context.save()
    }

    private func move(from src: IndexSet, to dst: Int) {
        var arr = items
        arr.move(fromOffsets: src, toOffset: dst)
        for (i, item) in arr.enumerated() { item.order = i }
        try? context.save()
    }

    private func clearChecked() {
        for i in items where i.isChecked { context.delete(i) }
        try? context.save()
    }

    private func clearAll() {
        for i in items { context.delete(i) }
        try? context.save()
    }
}
