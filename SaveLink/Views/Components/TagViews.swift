//
//  TagViews.swift
//  SaveLink
//

import SwiftUI

struct TagChip: View {
    let tag: String
    var color: Color = Theme.brand
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.caption.weight(.semibold))
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Lays out children left to right, wrapping to new lines (for tag chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > maxWidth {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// Edits a list of tags: chips with remove buttons, a text field and suggestions from existing tags.
struct TagEditor: View {
    @Binding var tags: [String]
    var knownTags: [String] = []
    var color: Color = Theme.brand
    @State private var draft = ""

    private var suggestions: [String] {
        let query = TagFormatter.clean(draft)
        return knownTags
            .filter { !tags.contains($0) && (query.isEmpty || $0.hasPrefix(query)) }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                FlowLayout {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(tag: tag, color: color) {
                            withAnimation(.snappy) { tags.removeAll { $0 == tag } }
                        }
                    }
                }
            }
            HStack {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                TextField("Add a tag", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addDraft)
                    .onChange(of: draft) { _, newValue in
                        // A comma or space finishes the tag.
                        if newValue.hasSuffix(",") || newValue.hasSuffix(" ") { addDraft() }
                    }
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { tag in
                            Button {
                                withAnimation(.snappy) { tags = TagFormatter.merge(tags, [tag]) }
                                draft = ""
                            } label: {
                                TagChip(tag: tag, color: .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func addDraft() {
        let tag = TagFormatter.clean(draft.trimmingCharacters(in: CharacterSet(charactersIn: ", ")))
        draft = ""
        guard !tag.isEmpty else { return }
        withAnimation(.snappy) { tags = TagFormatter.merge(tags, [tag]) }
    }
}
