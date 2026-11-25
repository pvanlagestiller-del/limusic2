import Foundation

/// Stellt die Inhalte der einzelnen Bereiche zusammen (mit kurzem Zwischenspeicher).
@MainActor
enum Feeds {
    private static var cache: [String: (Date, [Shelf])] = [:]
    private static let ttl: TimeInterval = 300

    static func clearCache() { cache = [:] }

    static func load(_ kind: FeedKind, mode: AppMode, force: Bool) async throws -> [Shelf] {
        let key = "\(kind.rawValue)-\(mode.rawValue)"
        if !force, let entry = cache[key], Date().timeIntervalSince(entry.0) < ttl {
            return entry.1
        }
        var shelves: [Shelf]
        switch (kind, mode) {
        case (.home, .video):     shelves = try await videoHome()
        case (.home, .music):     shelves = try await musicHome()
        case (.explore, .video):  shelves = try await videoExplore()
        case (.explore, .music):  shelves = try await musicExplore()
        case (.library, .video):  shelves = try await videoLibrary()
        case (.library, .music):  shelves = try await musicLibrary()
        }
        // Wie bei YouTube: Antippen spielt den Titel und danach Passendes dazu.
        // Bibliothek (Playlists, Verlauf) und Shorts-Reihen bleiben in ihrer Reihenfolge.
        if kind != .library {
            for i in shelves.indices where shelves[i].style != .shorts { shelves[i].radio = true }
        }
        cache[key] = (Date(), shelves)
        return shelves
    }

    private static let tube = InnerTube.shared
    private static var tokens: [String: String] = [:]

    static func hasMore(_ kind: FeedKind, mode: AppMode) -> Bool {
        tokens["\(kind.rawValue)-\(mode.rawValue)"] != nil
    }

    /// Nächste Seite der Startseite (Endlos-Scrollen)
    static func more(_ kind: FeedKind, mode: AppMode) async throws -> [Shelf] {
        let key = "\(kind.rawValue)-\(mode.rawValue)"
        guard let token = tokens[key] else { return [] }
        let music = mode == .music
        let r = try await tube.browseContinuation(token, client: music ? .music : .web)
        let parsed = await off { Parser.shelves(r, music: music) }
        let next = await off { Parser.continuationToken(r) }
        tokens[key] = next == token ? nil : next
        var out = parsed.shelves.filter { !$0.title.isEmpty }
        if !parsed.loose.isEmpty {
            out.append(Shelf(title: "", items: parsed.loose, style: music ? .grid : .list))
        }
        for i in out.indices where out[i].style != .shorts { out[i].radio = true }
        return out
    }

    /// Große YouTube-Antworten nicht auf dem Haupt-Thread auswerten (sonst ruckelt die Oberfläche).
    private static func off<T: Sendable>(_ work: @escaping () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }

    // MARK: Start

    private static func videoHome() async throws -> [Shelf] {
        let rec = try await tube.browse("FEwhat_to_watch", client: .web)
        let parsed = await off { Parser.shelves(rec, music: false) }
        tokens["home-video"] = await off { Parser.continuationToken(rec) }
        var out: [Shelf] = []
        var main = parsed.loose
        if let first = main.first {
            out.append(Shelf(title: "", items: [first], style: .featured))
            main.removeFirst()
        }
        if let hist = try? await tube.browse("FEhistory", client: .web) {
            let items = await off { Array(Parser.allItems(hist, music: false).prefix(15)) }
            if !items.isEmpty { out.append(Shelf(title: "Weiterschauen", items: items, style: .carousel, isHistory: true)) }
        }
        out += parsed.shelves.filter { !$0.title.isEmpty }
        if !main.isEmpty { out.append(Shelf(title: "Für dich", items: main, style: .list)) }
        return out
    }

    private static func musicHome() async throws -> [Shelf] {
        let home = try await tube.browse("FEmusic_home", client: .music)
        tokens["home-music"] = await off { Parser.continuationToken(home) }
        var out: [Shelf] = []
        if let hist = try? await tube.browse("FEmusic_history", client: .music) {
            let items = await off { Array(Parser.allItems(hist, music: true).prefix(15)) }
            if !items.isEmpty { out.append(Shelf(title: "Zuletzt gehört", items: items, style: .carousel)) }
        }
        let parsed = await off { Parser.shelves(home, music: true) }
        out += parsed.shelves.map { s in
            var s = s
            if s.title.isEmpty { s = Shelf(title: "Musik für dich", items: s.items, style: .carousel) }
            return s
        }
        if !parsed.loose.isEmpty { out.append(Shelf(title: "Mehr für dich", items: parsed.loose, style: .carousel)) }
        return out
    }

    // MARK: Entdecken

    private static func videoExplore() async throws -> [Shelf] {
        var out: [Shelf] = []
        if let subs = try? await tube.browse("FEsubscriptions", client: .web) {
            let items = await off { Parser.allItems(subs, music: false) }
            if !items.isEmpty { out.append(Shelf(title: "Neu von deinen Abos", items: Array(items.prefix(30)), style: .carousel)) }
        }
        for (title, query) in [("Neue Musikvideos", "neue musikvideos"), ("Gaming", "gaming highlights"),
                               ("Nachrichten", "nachrichten heute"), ("Sport", "sport highlights")] {
            if let r = try? await tube.search(query, client: .web) {
                let items = await off { Parser.allItems(r, music: false) }
                if !items.isEmpty { out.append(Shelf(title: title, items: Array(items.prefix(20)), style: .carousel)) }
            }
        }
        if out.isEmpty { throw LiMusicError(message: "Keine Inhalte gefunden. Prüfe die Internetverbindung.") }
        return out
    }

    private static func musicExplore() async throws -> [Shelf] {
        let r = try await tube.browse("FEmusic_explore", client: .music)
        var shelves = await off { Parser.shelves(r, music: true).shelves.filter { !$0.title.isEmpty } }
        if let nr = try? await tube.browse("FEmusic_new_releases", client: .music) {
            shelves += await off { Parser.shelves(nr, music: true).shelves.filter { !$0.title.isEmpty } }
        }
        return shelves
    }

    // MARK: Bibliothek

    private static func videoLibrary() async throws -> [Shelf] {
        var out: [Shelf] = []
        if let r = try? await tube.browse("FEchannels", client: .web) {
            let subs = await off { Parser.allItems(r, music: false).filter { $0.isChannel } }
            if !subs.isEmpty { out.append(Shelf(title: "Abos", items: subs, style: .carousel)) }
        }
        for (title, id) in [("Verlauf", "FEhistory"), ("Später ansehen", "VLWL"), ("Mag ich", "VLLL")] {
            if let r = try? await tube.browse(id, client: .web) {
                let items = await off { Parser.allItems(r, music: false) }
                if !items.isEmpty {
                    out.append(Shelf(title: title, items: Array(items.prefix(40)), style: .carousel,
                                     isHistory: id == "FEhistory"))
                }
            }
        }
        if let mine = try? await myPlaylists(), !mine.isEmpty {
            out.append(Shelf(title: "Deine YouTube-Playlists", items: mine, style: .carousel))
        }
        let loggedIn = await tube.isLoggedIn()
        if out.isEmpty && !loggedIn {
            throw LiMusicError(message: "Melde dich unter „Profil“ an, um deine Bibliothek zu sehen.")
        }
        return out
    }

    private static func musicLibrary() async throws -> [Shelf] {
        var out: [Shelf] = []
        for (title, id) in [("Lieblingssongs", "VLLM"), ("Zuletzt gehört", "FEmusic_history"),
                            ("Deine Playlists", "FEmusic_liked_playlists"), ("Deine Alben", "FEmusic_liked_albums")] {
            if let r = try? await tube.browse(id, client: .music) {
                let items = await off { Parser.allItems(r, music: true) }
                if !items.isEmpty { out.append(Shelf(title: title, items: Array(items.prefix(40)), style: .carousel)) }
            }
        }
        let loggedIn = await tube.isLoggedIn()
        if out.isEmpty && !loggedIn {
            throw LiMusicError(message: "Melde dich unter „Profil“ an, um deine Bibliothek zu sehen.")
        }
        return out
    }

    // MARK: Suche / Sammlungen / Warteschlange

    static func search(_ q: String, mode: AppMode, filter: MusicFilter = .all, video: VideoFilter = .all) async throws -> [Shelf] {
        var shelves = try await searchRaw(q, mode: mode, filter: filter, video: video)
        for i in shelves.indices { shelves[i].radio = true }
        return shelves
    }

    private static func searchRaw(_ q: String, mode: AppMode, filter: MusicFilter, video: VideoFilter) async throws -> [Shelf] {
        if mode == .video {
            let r = try await tube.search(q, client: .web, params: video.params)
            let items = await off { Parser.allItems(r, music: false) }
            let videos = items.filter { $0.videoId != nil && $0.duration != "Mix" && !$0.isShort }
            let shorts = items.filter { $0.isShort }
            let mixes = items.filter { $0.videoId != nil && $0.duration == "Mix" }
            let channels = items.filter { $0.isChannel }
            let lists = items.filter { $0.videoId == nil && !$0.isChannel }
            let wide: Int? = video == .all ? 8 : nil
            var out: [Shelf] = []
            if !channels.isEmpty {
                out.append(Shelf(title: "Kanäle", items: channels, style: video == .channels ? .grid : .carousel))
            }
            if !videos.isEmpty { out.append(Shelf(title: "Videos", items: videos, style: .grid, limit: wide)) }
            if !shorts.isEmpty { out.append(Shelf(title: "Shorts", items: shorts, style: .shorts)) }
            if !lists.isEmpty { out.append(Shelf(title: "Playlists", items: lists, style: .grid, limit: 4)) }
            if !mixes.isEmpty { out.append(Shelf(title: "Mixe", items: mixes, style: .grid, limit: 4)) }
            return out
        }
        let r = try await tube.search(q, client: .music, params: filter.params)
        let parsed = await off { Parser.shelves(r, music: true) }
        let lim: Int? = filter == .all ? 6 : nil
        var out = parsed.shelves.map {
            Shelf(title: $0.title.isEmpty ? "Ergebnisse" : $0.title, items: $0.items, style: .grid, limit: lim)
        }
        if !parsed.loose.isEmpty {
            out.append(Shelf(title: "Weitere Ergebnisse", items: parsed.loose, style: .grid, limit: lim))
        }
        if filter == .all, let top = await off({ Parser.topResult(r) }) {
            out.insert(Shelf(title: "Top-Ergebnis", items: [top], style: .list), at: 0)
        }
        // Reihenfolge: Titel, Interpreten, Alben, Videos, Playlists, Rest
        let order = ["titel", "song", "künstler", "interpret", "artist", "alben", "album", "video", "playlist"]
        func rank(_ t: String) -> Int {
            let l = t.lowercased()
            if l == "top-ergebnis" { return -1 }
            return order.firstIndex { l.contains($0) } ?? order.count
        }
        return out.enumerated().sorted { a, b in
            let ra = rank(a.element.title), rb = rank(b.element.title)
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map { $0.element }
    }

    static func collection(_ item: MediaItem) async throws -> [Shelf] {
        guard let bid = item.browseId else { return [] }
        // Kanalseite (normaler YouTube-Kanal)
        if bid.hasPrefix("UC") && !item.isMusic {
            var out: [Shelf] = []
            if let vr = try? await tube.browse(bid, client: .web, params: "EgZ2aWRlb3PyBgQKAjoA") {
                let vids = await off { Parser.allItems(vr, music: false).filter { $0.videoId != nil } }
                if !vids.isEmpty { out.append(Shelf(title: "Neueste Videos", items: vids, style: .grid, limit: 8)) }
            }
            if let hr = try? await tube.browse(bid, client: .web) {
                let parsed = await off { Parser.shelves(hr, music: false) }
                out += parsed.shelves.filter { !$0.title.isEmpty }
            }
            if out.isEmpty { throw LiMusicError(message: "Kanalseite konnte nicht geladen werden.") }
            return out
        }
        // Interpreten-Seite
        if bid.hasPrefix("UC") {
            let ar = try await tube.browse(bid, client: .music)
            let parsed = await off { Parser.shelves(ar, music: true) }
            let shelves = parsed.shelves.map { s -> Shelf in
                let allSongs = s.items.allSatisfy { $0.videoId != nil && !$0.hasVideo }
                return Shelf(title: s.title.isEmpty ? "Titel" : s.title, items: s.items,
                             style: allSongs ? .list : .carousel)
            }
            if shelves.isEmpty { throw LiMusicError(message: "Interpreten-Seite konnte nicht geladen werden.") }
            return shelves
        }
        // Mixe/Radios lassen sich nicht „browsen“ – Warteschlange des Mixes holen
        if bid.hasPrefix("VLRD") || bid.hasPrefix("RD") {
            let pid = bid.hasPrefix("VL") ? String(bid.dropFirst(2)) : bid
            let seed = pid.count == 13 ? String(pid.dropFirst(2)) : ""
            let mr = try await tube.next(videoId: seed, playlistId: pid, client: item.isMusic ? .music : .web)
            let music = item.isMusic
            let items = await off { Parser.allItems(mr, music: music) }
            return [Shelf(title: "", items: items, style: .list)]
        }
        let r = try await tube.browse(bid, client: item.isMusic ? .music : .web)
        let music = item.isMusic
        let itemId = item.id
        let items = await off { Parser.allItems(r, music: music).filter { $0.id != itemId } }
        return [Shelf(title: "", items: items, style: .list)]
    }

    /// Eigene Playlists im YouTube-Konto
    static func myPlaylists() async throws -> [MediaItem] {
        let r = try await tube.browse("FEplaylist_aggregation", client: .web)
        return await off {
            Parser.allItems(r, music: false).filter { ($0.browseId ?? "").hasPrefix("VLPL") }
        }
    }

    /// Ersatz für Benachrichtigungen: wie viele neue Abo-Videos seit dem letzten Öffnen?
    static func newSubscriptionCount() async -> Int {
        guard let r = try? await tube.browse("FEsubscriptions", client: .web) else { return 0 }
        let ids = await off { Array(Parser.allItems(r, music: false).compactMap { $0.videoId }.prefix(40)) }
        guard !ids.isEmpty else { return 0 }
        let seen = Set(UserDefaults.standard.stringArray(forKey: "seenSubscriptionVideos") ?? [])
        UserDefaults.standard.set(ids, forKey: "seenSubscriptionVideos")
        if seen.isEmpty { return 0 }
        return ids.filter { !seen.contains($0) }.count
    }

    static func lyrics(videoId: String) async -> String? {
        guard let n = try? await tube.next(videoId: videoId, playlistId: nil, client: .music) else { return nil }
        let lyricsId: String? = await off {
            var ids: [String] = []
            Parser.collectStrings(n, key: "browseId", into: &ids)
            return ids.first { $0.hasPrefix("MPLY") }
        }
        guard let lyricsId, let b = try? await tube.browse(lyricsId, client: .music) else { return nil }
        let result: String? = await off {
            guard let shelf = Parser.findValue(b, key: "musicDescriptionShelfRenderer") as? [String: Any] else { return nil }
            let t = Parser.text(shelf["description"])
            return t.isEmpty ? nil : t
        }
        return result
    }

    static func related(videoId: String, music: Bool) async -> [MediaItem] {
        let r: [String: Any]?
        if music {
            r = try? await tube.next(videoId: videoId, playlistId: "RDAMVM\(videoId)", client: .music)
        } else {
            r = try? await tube.next(videoId: videoId, playlistId: nil, client: .web)
        }
        guard let r else { return [] }
        return await off { Parser.allItems(r, music: music).filter { $0.videoId != nil && $0.videoId != videoId } }
    }
}

/// Suchvorschläge beim Tippen (YouTube-Vorschlagsdienst)
enum Suggest {
    static func fetch(_ q: String) async -> [String] {
        guard var c = URLComponents(string: "https://suggestqueries.google.com/complete/search") else { return [] }
        c.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "ds", value: "yt"),
            URLQueryItem(name: "hl", value: "de"),
            URLQueryItem(name: "ie", value: "utf-8"),
            URLQueryItem(name: "oe", value: "utf-8"),
            URLQueryItem(name: "q", value: q)
        ]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        var obj: Any? = try? JSONSerialization.jsonObject(with: data)
        if obj == nil, let s = String(data: data, encoding: .isoLatin1), let d = s.data(using: .utf8) {
            obj = try? JSONSerialization.jsonObject(with: d)
        }
        guard let arr = obj as? [Any], arr.count > 1, let list = arr[1] as? [Any] else { return [] }
        return Array(list.compactMap { $0 as? String }.prefix(8))
    }
}
