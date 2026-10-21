import LanguifyKit
import SwiftData
import SwiftUI

struct VocabularyListView: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \VocabularyEntry.lastEncounteredAt, order: .reverse) private var entries: [VocabularyEntry]
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var languageFilter: HeritageLanguage?
    @State private var showAdd = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", favorites = "Favorites", learning = "Learning", mastered = "Mastered"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            let results = filtered
            List {
                if !entries.isEmpty {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                ForEach(results) { entry in
                    NavigationLink(value: entry.id) {
                        VocabularyRow(entry: entry)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            services.repository.delete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            services.repository.toggleFavorite(entry)
                        } label: {
                            Label(entry.isFavorite ? "Unfavorite" : "Favorite", systemImage: entry.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No words yet", systemImage: "character.book.closed")
                    } description: {
                        Text("Words you ask about during Live Rewind are saved here automatically, with the sentence they came from.")
                    } actions: {
                        Button("Add a word yourself") { showAdd = true }
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Search words or meanings")
            .navigationTitle("Vocabulary")
            .navigationDestination(for: UUID.self) { id in
                if let entry = entries.first(where: { $0.id == id }) {
                    VocabularyDetailView(entry: entry)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Language", selection: $languageFilter) {
                            Text("All languages").tag(HeritageLanguage?.none)
                            ForEach(HeritageLanguage.allCases) { Text($0.displayName).tag(Optional($0)) }
                        }
                    } label: {
                        Label("Language", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Label("Add word", systemImage: "plus") }
                }
                if !entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            FlashcardSessionView()
                        } label: {
                            Label("Practice", systemImage: "rectangle.stack")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                EditVocabularyView(entry: nil)
            }
        }
    }

    private var filtered: [VocabularyEntry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { entry in
            if let languageFilter, entry.languageCode != languageFilter.rawValue { return false }
            switch filter {
            case .all: break
            case .favorites: if !entry.isFavorite { return false }
            case .learning: if entry.status == .mastered { return false }
            case .mastered: if entry.status != .mastered { return false }
            }
            guard !query.isEmpty else { return true }
            return entry.transliteration.lowercased().contains(query)
                || entry.nativeScript.contains(query)
                || entry.englishMeaning.lowercased().contains(query)
                || entry.contextualMeaning.lowercased().contains(query)
        }
    }
}

struct VocabularyRow: View {
    let entry: VocabularyEntry
    var body: some View {
        HStack(alignment: .top) {
            PhraseView(nativeScript: entry.nativeScript, transliteration: entry.transliteration, english: entry.englishMeaning, size: .compact)
            VStack(alignment: .trailing, spacing: 6) {
                StatusBadge(status: entry.status)
                if entry.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                        .accessibilityLabel("Favorite")
                }
            }
        }
        .padding(.vertical, 4)
    }
}
