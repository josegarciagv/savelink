//
//  ReaderView.swift
//  SaveLink
//
//  Offline reading with highlights and notes. The page text is saved with the link,
//  so it opens without internet.
//

import SwiftUI
import SwiftData

enum ReaderExtractor {
    /// Downloads the page and returns its readable paragraphs separated by blank lines.
    nonisolated static func readableText(from url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }

        // Prefer the <article>/<main> part of the page when there is one.
        let body = html.firstMatch(of: /(?is)<article[^>]*>(.*?)<\/article>/).map { String($0.1) }
            ?? html.firstMatch(of: /(?is)<main[^>]*>(.*?)<\/main>/).map { String($0.1) }
            ?? html
        let cleaned = body.replacing(/(?is)<(script|style|noscript|svg|nav|footer|header|aside|form)[^>]*>.*?<\/\1>/, with: " ")

        let paragraphs = cleaned.matches(of: /(?is)<(p|h1|h2|h3|li|blockquote)[^>]*>(.*?)<\/\1>/).compactMap { match -> String? in
            let text = decode(String(match.2).replacing(/<[^>]+>/, with: ""))
                .replacing(/\s+/, with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.count >= 40 || (match.1.lowercased().hasPrefix("h") && text.count >= 3) ? text : nil
        }
        guard paragraphs.count >= 2 else { return nil }
        return paragraphs.joined(separator: "\n\n")
    }

    nonisolated private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&rsquo;", with: "’")
            .replacingOccurrences(of: "&lsquo;", with: "‘")
            .replacingOccurrences(of: "&ldquo;", with: "“")
            .replacingOccurrences(of: "&rdquo;", with: "”")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var link: Link
    @AppStorage("readerFontSize") private var fontSize: Double = 19
    @AppStorage("readerSerif") private var useSerif = true
    @State private var isLoading = false
    @State private var failed = false
    @State private var showNotes = false

    private var tint: Color { .folder(link.folder?.color) }

    private var paragraphs: [String] {
        (link.readerText ?? "").components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if link.readerText != nil {
                    article
                } else if isLoading {
                    ProgressView("Saving page for offline reading…")
                } else {
                    ContentUnavailableView {
                        Label(failed ? "Can't Read This Page" : "Read Offline", systemImage: failed ? "doc.text.magnifyingglass" : "arrow.down.doc")
                    } description: {
                        Text(failed
                             ? "This page doesn't have readable text, or you're offline."
                             : "Save the text of this page to read it anywhere, even without internet.")
                    } actions: {
                        Button(failed ? "Try Again" : "Save Page") { Task { await download() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if link.readerText != nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showNotes = true
                        } label: {
                            Image(systemName: link.notes?.isEmpty == false ? "note.text" : "square.and.pencil")
                        }
                        .accessibilityLabel("Notes")
                        Menu {
                            Button {
                                fontSize = min(fontSize + 2, 30)
                            } label: {
                                Label("Larger Text", systemImage: "textformat.size.larger")
                            }
                            Button {
                                fontSize = max(fontSize - 2, 14)
                            } label: {
                                Label("Smaller Text", systemImage: "textformat.size.smaller")
                            }
                            Toggle("Serif Font", isOn: $useSerif)
                            Divider()
                            Button {
                                Task { await download() }
                            } label: {
                                Label("Refresh Saved Page", systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) {
                                link.readerText = nil
                                link.readerSavedAt = nil
                                link.modelContext?.saveAndBackup()
                            } label: {
                                Label("Remove Offline Copy", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "textformat.size")
                        }
                    }
                }
            }
            .sheet(isPresented: $showNotes) {
                NotesEditor(link: link)
            }
            .task {
                if link.readerText == nil { await download() }
            }
        }
        .tint(tint)
    }

    private var article: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(link.domain.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(link.name)
                        .font(.system(.title, design: useSerif ? .serif : .default).weight(.bold))
                    if let saved = link.readerSavedAt {
                        Text("Saved \(saved.formatted(.relative(presentation: .named))) · \(readingMinutes) min read")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)

                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    let highlighted = link.highlights.contains(paragraph)
                    Text(paragraph)
                        .font(.system(size: fontSize, design: useSerif ? .serif : .default))
                        .lineSpacing(fontSize * 0.35)
                        .textSelection(.enabled)
                        .padding(.horizontal, highlighted ? 8 : 0)
                        .padding(.vertical, highlighted ? 4 : 0)
                        .background(highlighted ? Color.yellow.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contextMenu {
                            Button {
                                toggleHighlight(paragraph)
                            } label: {
                                Label(highlighted ? "Remove Highlight" : "Highlight", systemImage: highlighted ? "highlighter" : "highlighter")
                            }
                            Button {
                                UIPasteboard.general.string = paragraph
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            ShareLink(item: "“\(paragraph)”\n— \(link.name) \(link.url)") {
                                Label("Share Quote", systemImage: "quote.bubble")
                            }
                        }
                        .onTapGesture(count: 2) { toggleHighlight(paragraph) }
                }

                Text("Double-tap or long-press a paragraph to highlight it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
            .padding(24)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var readingMinutes: Int {
        max(1, (link.readerText ?? "").split(separator: " ").count / 230)
    }

    private func toggleHighlight(_ paragraph: String) {
        if let index = link.highlights.firstIndex(of: paragraph) {
            link.highlights.remove(at: index)
        } else {
            link.highlights.append(paragraph)
        }
        link.modelContext?.saveAndBackup()
        Haptics.tap()
    }

    private func download() async {
        guard let url = URL(string: Link.normalizedURLString(link.url)) else { return }
        isLoading = true
        failed = false
        if let text = await ReaderExtractor.readableText(from: url) {
            link.readerText = text
            link.readerSavedAt = Date()
            // Drop highlights that no longer exist in the refreshed text.
            link.highlights = link.highlights.filter { text.contains($0) }
            link.modelContext?.saveAndBackup()
        } else {
            failed = true
        }
        isLoading = false
    }
}

private struct NotesEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var link: Link
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            link.notes = trimmed.isEmpty ? nil : trimmed
                            link.modelContext?.saveAndBackup()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
                .onAppear { text = link.notes ?? "" }
        }
        .presentationDetents([.medium, .large])
    }
}
