import AppFoundation
import Foundation

/// URL ↔ `DeepLinkRoute` saf çözümleyici/üretici (02 §8). Durumsuz; tüm metotlar
/// statik ve deterministiktir (test edilebilir çekirdek). Çözümleme kuralları §8.4:
/// bilinmeyen path → nil, ID format regex'i geçmeyen değer düşürülür (injection savunması).
public enum DeepLinkResolver {
    /// Custom scheme (§8.1): push payload'ları ve uygulama içi rotalar.
    public static let scheme = "shortseries"
    /// Universal link host'u (§8.1): paylaşım linkleri, web'den geçiş.
    public static let universalHost = "shortseries.app"

    /// §8.4 kural 4: sunucu içerik ID format sözleşmesi. Bu regex'i geçmeyen
    /// `seriesId`/`episodeId` deep link'i düşürülür (path injection'a set edilemez).
    static let contentIDPattern = "^[a-z]{3}_[A-Za-z0-9]{6,24}$"

    /// ID biçim doğrulaması (§8.4 kural 4). Ham `String`; boş/biçimsiz → false.
    public static func isValidContentID(_ id: String) -> Bool {
        id.range(of: contentIDPattern, options: .regularExpression) != nil
    }

    // MARK: - Çözümleme (URL → Route)

    /// Custom scheme veya `shortseries.app` universal link'ini tipli rotaya çevirir.
    /// Yabancı host / bilinmeyen scheme / bilinmeyen path / biçimsiz ID → nil.
    public static func route(from url: URL) -> DeepLinkRoute? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let segments = segments(from: components)
        else { return nil }
        let query = queryMap(components.queryItems)
        return route(segments: segments, query: query)
    }

    /// Şema ayrımı: custom scheme'de host mantıksal ilk segmenttir; universal link'te
    /// host domain'dir ve segmentler yalnız path'ten gelir. Yabancı host → nil.
    private static func segments(from components: URLComponents) -> [String]? {
        // URLComponents.path getter percent-encoding'i çözer (decoded döner).
        let pathSegments = components.path.split(separator: "/").map(String.init)
        switch components.scheme?.lowercased() {
        case scheme:
            guard let host = components.host, !host.isEmpty else {
                // "shortseries:///discover" gibi host'suz biçim de kabul: path yeter.
                return pathSegments.isEmpty ? nil : pathSegments
            }
            return [host] + pathSegments
        case "https", "http":
            guard components.host?.lowercased() == universalHost else { return nil }
            return pathSegments
        default:
            return nil
        }
    }

    private static func queryMap(_ items: [URLQueryItem]?) -> [String: String] {
        guard let items else { return [:] }
        // İlk değer kazanır; boş değerli parametre atlanır (yok sayılır).
        var map: [String: String] = [:]
        for item in items {
            guard let value = item.value, !value.isEmpty, map[item.name] == nil else { continue }
            map[item.name] = value
        }
        return map
    }

    /// Segment tablosu §8.2 ile bire bir. Custom scheme uzun sözcük (series/episode),
    /// universal link kısa harf (s/e) kullanır — ikisi de kabul edilir. Dallanma (ternary/if)
    /// yardımcılara taşınır; dispatcher saf switch kalır (cyclomatic complexity düşük).
    private static func route(segments: [String], query: [String: String]) -> DeepLinkRoute? {
        guard let head = segments.first else { return nil }
        let rest = Array(segments.dropFirst())
        // İki dar dispatcher (içerik + sekme); bilinmeyen head her ikisinde de nil → nil.
        return contentRoute(head: head, rest: rest, query: query)
            ?? tabRoute(head: head, rest: rest, query: query)
    }

    /// Parametreli/çok segmentli rotalar (series/episode/play/rewards/store).
    private static func contentRoute(head: String, rest: [String], query: [String: String]) -> DeepLinkRoute? {
        switch head {
        case "series", "s": seriesRoute(rest: rest)
        case "play": playRoute(rest: rest, query: query)
        case "rewards": rewardsRoute(rest: rest)
        case "store": storeRoute(rest: rest, query: query)
        default: nil
        }
    }

    /// Tek segmentli sekme/ekran rotaları (rest boş olmalı).
    private static func tabRoute(head: String, rest: [String], query: [String: String]) -> DeepLinkRoute? {
        switch head {
        case "home": only(rest, .home)
        case "discover": only(rest, .discover(genre: query["genre"]))
        case "search": only(rest, .search(query: query["q"]))
        case "mylist": only(rest, .myList(segment: query["segment"].flatMap(MyListSegment.init(rawValue:))))
        case "profile": only(rest, .profile)
        case "settings": only(rest, .settings(section: query["section"]))
        case "notifications": only(rest, .notifications)
        default: nil
        }
    }

    /// `rest` boşsa rotayı döndürür, aksi halde nil (fazladan path segmenti = bilinmeyen path).
    private static func only(_ rest: [String], _ route: @autoclosure () -> DeepLinkRoute) -> DeepLinkRoute? {
        rest.isEmpty ? route() : nil
    }

    private static func seriesRoute(rest: [String]) -> DeepLinkRoute? {
        guard let id = rest.first, isValidContentID(id) else { return nil }
        let seriesID = SeriesID(id)
        if rest.count == 1 {
            return .series(id: seriesID)
        }
        // /series/{id}/episode/{n} veya /s/{id}/e/{n}
        guard rest.count == 3, rest[1] == "episode" || rest[1] == "e" else { return nil }
        guard let number = Int(rest[2]), number > 0 else { return nil }
        return .episode(seriesId: seriesID, number: number)
    }

    private static func playRoute(rest: [String], query: [String: String]) -> DeepLinkRoute? {
        guard rest.count == 1, isValidContentID(rest[0]) else { return nil }
        return .play(seriesId: SeriesID(rest[0]), startSeconds: query["t"].flatMap(Int.init))
    }

    private static func rewardsRoute(rest: [String]) -> DeepLinkRoute? {
        if rest.isEmpty {
            return .rewards(anchor: nil)
        }
        return rest == ["checkin"] ? .rewards(anchor: .checkin) : nil
    }

    private static func storeRoute(rest: [String], query: [String: String]) -> DeepLinkRoute? {
        if rest == ["coins"] {
            return .coinStore(offer: query["offer"])
        }
        if rest == ["vip"] {
            return .vip(preselectedPlan: query["plan"])
        }
        return nil
    }

    // MARK: - Üretim (Route → URL)

    /// Paylaşım/web geçiş linki (§8.1.1: `/s/{id}`, `/s/{id}/e/{n}`...).
    public static func universalLink(for route: DeepLinkRoute) -> URL {
        makeURL(scheme: "https", host: universalHost, route: route, useShortPaths: true)
    }

    /// Uygulama içi / push custom scheme linki.
    public static func customScheme(for route: DeepLinkRoute) -> URL {
        makeURL(scheme: scheme, host: nil, route: route, useShortPaths: false)
    }

    /// DiziDetay "paylaş" CTA'sı (02 §4.4): universal link, shortseries.app dom'ain.
    public static func shareLink(forSeries id: SeriesID) -> URL {
        universalLink(for: .series(id: id))
    }

    /// DiziDetay'dan belirli bir bölümü paylaşma (§8.1.1 `/s/{id}/e/{n}`).
    public static func shareLink(forSeries id: SeriesID, episodeNumber: Int) -> URL {
        universalLink(for: .episode(seriesId: id, number: episodeNumber))
    }

    private static func makeURL(scheme: String, host: String?, route: DeepLinkRoute, useShortPaths: Bool) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        let (segments, query) = pathAndQuery(for: route, useShortPaths: useShortPaths)
        if let host {
            // Universal link: host domain, path segmentleri.
            components.host = host
            components.path = "/" + segments.joined(separator: "/")
        } else {
            // Custom scheme: ilk segment host, kalanı path (URLComponents kalıbı).
            components.host = segments.first
            let tail = segments.dropFirst()
            components.path = tail.isEmpty ? "" : "/" + tail.joined(separator: "/")
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        // Sabit şema/host/segment kümesi her zaman geçerli bir URL üretir; teorik nil'de
        // /home'a düşülür (deep link üretimi hiçbir zaman çökmemeli).
        return components.url ?? fallbackURL(scheme: scheme, host: host)
    }

    private static func fallbackURL(scheme: String, host: String?) -> URL {
        let base = host.map { "\(scheme)://\($0)/home" } ?? "\(scheme)://home"
        return URL(string: base) ?? URL(fileURLWithPath: "/")
    }

    /// Tek opsiyonel sorgu parametresi; değer nil ise boş liste (dallanma pathAndQuery'den çıkar).
    private static func singleQuery(_ name: String, _ value: String?) -> [URLQueryItem] {
        value.map { [URLQueryItem(name: name, value: $0)] } ?? []
    }

    /// Üç dar mapper birleşimi (içerik + mağaza/ödül + sekme); exhaustive kapsam korunur.
    private static func pathAndQuery(
        for route: DeepLinkRoute,
        useShortPaths: Bool
    ) -> (segments: [String], query: [URLQueryItem]) {
        contentPathAndQuery(for: route, useShortPaths: useShortPaths)
            ?? storePathAndQuery(for: route)
            ?? tabPathAndQuery(for: route)
    }

    private static func contentPathAndQuery(
        for route: DeepLinkRoute,
        useShortPaths: Bool
    ) -> (segments: [String], query: [URLQueryItem])? {
        let seriesHead = useShortPaths ? "s" : "series"
        let episodeHead = useShortPaths ? "e" : "episode"
        switch route {
        case let .series(id):
            return ([seriesHead, id.rawValue], [])
        case let .episode(seriesId, number):
            return ([seriesHead, seriesId.rawValue, episodeHead, String(number)], [])
        case let .play(seriesId, startSeconds):
            return (["play", seriesId.rawValue], singleQuery("t", startSeconds.map(String.init)))
        default:
            return nil
        }
    }

    private static func storePathAndQuery(for route: DeepLinkRoute) -> (segments: [String], query: [URLQueryItem])? {
        switch route {
        case let .rewards(anchor):
            (anchor == .checkin ? ["rewards", "checkin"] : ["rewards"], [])
        case let .coinStore(offer):
            (["store", "coins"], singleQuery("offer", offer))
        case let .vip(plan):
            (["store", "vip"], singleQuery("plan", plan))
        default:
            nil
        }
    }

    /// Tek segmentli sekme rotaları (içerik/mağaza yukarıda ele alındı → burada ulaşılmaz).
    private static func tabPathAndQuery(for route: DeepLinkRoute) -> (segments: [String], query: [URLQueryItem]) {
        switch route {
        case let .discover(genre):
            (["discover"], singleQuery("genre", genre))
        case let .search(queryText):
            (["search"], singleQuery("q", queryText))
        case let .myList(segment):
            (["mylist"], singleQuery("segment", segment?.rawValue))
        case let .settings(section):
            (["settings"], singleQuery("section", section))
        case .notifications:
            (["notifications"], [])
        case .profile:
            (["profile"], [])
        default:
            (["home"], [])
        }
    }
}
