import AppFoundation
import ContentKit
import Foundation
import Observation

/// Arama ekran modeli (SS-072/073). @Observable/@MainActor; SwiftUI View ince kalır. Debounce
/// kararı saf `SearchInputMachine`tedir; bu model zamanlama (debounce Task) + ağ + sayfalama +
/// analitiği yönetir. Boş durumda son + popüler aramalar; yazarken debounce'lu öneri; gönderimde
/// cursor sayfalı sonuç ızgarası; "sonuç yok" boş durumu.
@MainActor
@Observable
public final class AramaModel {
    /// Ekran modu (02 §4.11): boş sorgu (son+popüler) → öneri → sonuç → sonuç yok.
    public enum Phase: Equatable, Sendable {
        case browsing
        case suggesting
        case results
        case noResult(query: String)
    }

    // MARK: - Durum (Observable)

    public private(set) var phase: Phase = .browsing
    public private(set) var queryText = ""
    public private(set) var suggestions: [SearchSuggestion] = []
    public private(set) var results: [Series] = []
    public private(set) var recentSearches: [String] = []
    public private(set) var popularSearches: [String] = []
    public private(set) var isLoadingResults = false
    public private(set) var isLoadingMore = false
    /// Sonuç isteği hatası — satır içi hata + "Tekrar Dene"; yazılan sorgu korunur (§4.11).
    public private(set) var hasResultsError = false

    // MARK: - Bağımlılıklar

    private let search: any SearchServicing
    private let recentStore: any RecentSearchStoring
    private let analytics: any AnalyticsTracking
    private let source: AramaSource
    private let debounceInterval: Duration
    private let initialQuery: String?
    private weak var delegate: (any AramaDelegate)?

    private var machine = SearchInputMachine()
    private var debounceTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var nextCursor: String?
    private var lastSearchedQuery = ""
    private var appeared = false
    /// Sonuç isteklerinin (arama + sayfalama) kuşak jetonu. Her yeni `performSearch` bunu
    /// artırır; await sonrası eşleşmeyen (üstü örtülen) yanıt state'e YAZMAZ — böylece geç dönen
    /// eski sorgu yeni sonucu ezmez ve çapraz-sorgu sayfası yeni listeye karışmaz (§4.11).
    private var searchGeneration = 0

    public init(
        search: any SearchServicing,
        recentStore: any RecentSearchStoring,
        analytics: any AnalyticsTracking,
        delegate: (any AramaDelegate)?,
        source: AramaSource = .kesfet,
        initialQuery: String? = nil,
        debounceInterval: Duration = .milliseconds(300)
    ) {
        self.search = search
        self.recentStore = recentStore
        self.analytics = analytics
        self.delegate = delegate
        self.source = source
        self.initialQuery = initialQuery
        self.debounceInterval = debounceInterval
    }

    /// Sonuç sayfalamasının devamı var mı (View son hücrede `loadMore` tetikler).
    public var canLoadMore: Bool {
        nextCursor != nil
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        guard !appeared else { return }
        appeared = true
        analytics.track("search_open", parameters: ["source": .string(source.rawValue)])
        recentSearches = recentStore.load()
        Task { await loadPopular() }
        if let initialQuery, !initialQuery.isEmpty {
            queryText = initialQuery
            submit()
        }
    }

    func loadPopular() async {
        popularSearches = await (try? search.popular()) ?? []
    }

    // MARK: - Yazma (debounce'lu öneri, §4.11)

    /// Metin değişimi (View binding). <2 karakter → varsayılan mod; aksi halde debounce sonrası
    /// öneri. Her tuş askıdaki öneriyi iptal eder (yalnız en güncel sorgu render edilir).
    public func queryChanged(_ raw: String) {
        queryText = raw
        switch machine.onInput(raw) {
        case .browse:
            debounceTask?.cancel()
            debounceTask = nil
            suggestions = []
            phase = .browsing
        case let .scheduleSuggest(query, token):
            phase = .suggesting
            debounceTask?.cancel()
            let interval = debounceInterval
            debounceTask = Task { [weak self] in
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, machine.isCurrent(token) else { return }
                await performSuggest(query: query, token: token)
            }
        }
    }

    /// Öneri isteği; yalnız EN GÜNCEL token için uygulanır (sıra-dışı yanıt savunması, §4.11).
    func performSuggest(query: String, token: Int) async {
        guard machine.isCurrent(token) else { return }
        guard let incoming = try? await search.suggest(query: query) else { return }
        guard machine.isCurrent(token) else { return } // await sırasında yeni tuş geldiyse at
        suggestions = incoming
        phase = .suggesting
        trackSearchQuery(query: query, resultCount: incoming.count, isAutocomplete: true)
    }

    // MARK: - Gönderim → sonuç ızgarası (§4.11)

    /// Klavye "Ara" / öneri sorgusu / çip → sonuç modu.
    public func submit() {
        guard case let .showResults(query, _) = machine.onSubmit(queryText) else { return }
        queryText = query
        recordRecent(query)
        resultsTask?.cancel()
        resultsTask = Task { [weak self] in await self?.performSearch(query: query) }
    }

    func performSearch(query: String) async {
        debounceTask?.cancel()
        debounceTask = nil
        searchGeneration += 1
        let token = searchGeneration
        lastSearchedQuery = query
        phase = .results
        isLoadingResults = true
        hasResultsError = false
        do {
            let page = try await search.search(query: query, cursor: nil)
            // Üstü örtülen/iptal edilen sorgu: geçerli sonucu EZME.
            guard !Task.isCancelled, token == searchGeneration else { return }
            isLoadingResults = false
            results = page.items
            nextCursor = page.nextCursor
            if page.items.isEmpty {
                phase = .noResult(query: query)
                analytics.track("search_no_result", parameters: ["query": .string(query)])
                trackSearchQuery(query: query, resultCount: 0, isAutocomplete: false)
            } else {
                phase = .results
                trackSearchQuery(query: query, resultCount: page.items.count, isAutocomplete: false)
            }
        } catch {
            // İptal/supersede kaynaklı hata banner boyamaz; yalnız GÜNCEL sorgu hatası gösterilir.
            guard !Task.isCancelled, token == searchGeneration else { return }
            isLoadingResults = false
            hasResultsError = true
            phase = .results
        }
    }

    /// Sonsuz scroll bir sonraki sayfa (cursor sayfalama, 05 §7.1).
    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore, !isLoadingResults else { return }
        let token = searchGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await search.search(query: lastSearchedQuery, cursor: cursor) else { return }
        // Sorgu await sırasında değiştiyse bu sayfayı yeni listeye KARIŞTIRMA.
        guard token == searchGeneration else { return }
        results += page.items
        nextCursor = page.nextCursor
    }

    /// Sonuç hatası "Tekrar Dene" (§4.11): son sorguyu yeniden çalıştır.
    public func retryResults() {
        resultsTask?.cancel()
        resultsTask = Task { [weak self] in await self?.performSearch(query: self?.lastSearchedQuery ?? "") }
    }

    // MARK: - Seçimler

    /// Öneri dokunuşu: dizi önerisi → doğrudan `DiziDetay`; sorgu önerisi → sonuç modu.
    public func selectSuggestion(_ suggestion: SearchSuggestion) {
        switch suggestion.kind {
        case .series:
            guard let seriesID = suggestion.seriesID else { return }
            recordRecent(suggestion.text)
            delegate?.aramaDidSelectSeries(seriesID)
        case .query:
            queryText = suggestion.text
            submit()
        }
    }

    /// Son/popüler arama çipi → sorguyu doldur + ara (§4.11).
    public func selectQuery(_ query: String) {
        queryText = query
        submit()
    }

    /// Sonuç ızgarası kartı → `DiziDetay` (§4.11).
    public func selectResult(_ series: Series, position: Int) {
        analytics.track(
            "search_result_tap",
            parameters: [
                "query": .string(lastSearchedQuery),
                "series_id": .string(series.id.rawValue),
                "result_position": .int(position)
            ]
        )
        delegate?.aramaDidSelectSeries(series.id)
    }

    public func removeRecent(_ query: String) {
        recentStore.remove(query)
        recentSearches = recentStore.load()
    }

    public func clearRecents() {
        recentStore.clear()
        recentSearches = []
    }

    /// "İptal" → `Kesfet`'e döner.
    public func cancel() {
        delegate?.aramaRequestsDismiss()
    }

    /// Testler için: askıdaki debounce + sonuç görevlerini bekler (deterministik).
    func pendingWork() async {
        await debounceTask?.value
        await resultsTask?.value
    }

    // MARK: - İç

    private func recordRecent(_ query: String) {
        recentStore.add(query)
        recentSearches = recentStore.load()
    }

    private func trackSearchQuery(query: String, resultCount: Int, isAutocomplete: Bool) {
        analytics.track(
            "search_query",
            parameters: [
                "query": .string(query),
                "result_count": .int(resultCount),
                "is_autocomplete": .bool(isAutocomplete)
            ]
        )
    }
}
