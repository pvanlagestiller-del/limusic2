import Foundation
import WebKit
import CryptoKit

/// Zugriff auf YouTubes interne Web-Schnittstelle (dieselbe, die youtube.com selbst nutzt).
/// Anmeldung über die Cookies des WKWebView-Datenspeichers (Google-Login in der App).
final class InnerTube {
    static let shared = InnerTube()

    enum Client {
        case web, music
        var host: String { self == .web ? "https://www.youtube.com" : "https://music.youtube.com" }
        var name: String { self == .web ? "WEB" : "WEB_REMIX" }
        var nameId: String { self == .web ? "1" : "67" }
    }

    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private var versions: [String: String] = ["WEB": "2.20251110.01.00", "WEB_REMIX": "1.20251110.01.00"]
    private var visitorData: String?
    private var configLoaded = false

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    // MARK: Cookies / Anmeldung

    @MainActor
    func cookies() async -> [HTTPCookie] {
        await withCheckedContinuation { cont in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
    }

    func isLoggedIn() async -> Bool {
        let cs = await cookies()
        return cs.contains { $0.name == "SAPISID" && $0.domain.contains("youtube.com") }
    }

    func resetConfig() {
        configLoaded = false
        visitorData = nil
    }

    private func cookieHeader(_ cs: [HTTPCookie], for host: String) -> String {
        guard let h = URL(string: host)?.host else { return "" }
        return cs.filter { c in
            let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
            return h == d || h.hasSuffix("." + d)
        }
        .map { "\($0.name)=\($0.value)" }
        .joined(separator: "; ")
    }

    private func sha1Hex(_ s: String) -> String {
        Insecure.SHA1.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func authHeader(_ cs: [HTTPCookie], origin: String) -> String? {
        let ts = Int(Date().timeIntervalSince1970)
        func value(_ name: String) -> String? {
            cs.first { $0.name == name && $0.domain.contains("youtube.com") }?.value
        }
        var parts: [String] = []
        for (cookie, label) in [("SAPISID", "SAPISIDHASH"), ("__1PSAPISID", "SAPISID1PHASH"), ("__3PSAPISID", "SAPISID3PHASH")] {
            if let v = value(cookie) {
                parts.append("\(label) \(ts)_\(sha1Hex("\(ts) \(v) \(origin)"))")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Konfiguration (aktuelle Client-Version + VisitorData aus der Startseite)

    private func loadConfigIfNeeded() async {
        guard !configLoaded else { return }
        configLoaded = true
        let cs = await cookies()
        for client in [Client.web, .music] {
            guard let url = URL(string: client.host + "/") else { continue }
            var req = URLRequest(url: url)
            req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
            req.setValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
            req.setValue(cookieHeader(cs, for: client.host), forHTTPHeaderField: "Cookie")
            guard let (data, _) = try? await session.data(for: req),
                  let html = String(data: data, encoding: .utf8) else { continue }
            if let v = Self.match(html, #""INNERTUBE_CLIENT_VERSION":"([^"]+)""#) { versions[client.name] = v }
            if visitorData == nil, let vd = Self.match(html, #""VISITOR_DATA":"([^"]+)""#) { visitorData = vd }
        }
    }

    static func match(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    // MARK: Anfragen

    func call(_ endpoint: String, client: Client, body: [String: Any], query: String = "") async throws -> [String: Any] {
        await loadConfigIfNeeded()
        let cs = await cookies()

        var clientInfo: [String: Any] = [
            "clientName": client.name,
            "clientVersion": versions[client.name] ?? "",
            "hl": "de",
            "gl": "DE"
        ]
        if let vd = visitorData { clientInfo["visitorData"] = vd }
        var payload = body
        payload["context"] = ["client": clientInfo]

        guard let url = URL(string: "\(client.host)/youtubei/v1/\(endpoint)?prettyPrint=false\(query)") else {
            throw LiMusicError(message: "Ungültige Adresse")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue(client.host, forHTTPHeaderField: "Origin")
        req.setValue(client.host, forHTTPHeaderField: "X-Origin")
        req.setValue(client.nameId, forHTTPHeaderField: "X-Youtube-Client-Name")
        req.setValue(versions[client.name], forHTTPHeaderField: "X-Youtube-Client-Version")
        req.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        req.setValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue(cookieHeader(cs, for: client.host), forHTTPHeaderField: "Cookie")
        if let vd = visitorData { req.setValue(vd, forHTTPHeaderField: "X-Goog-Visitor-Id") }
        if let auth = authHeader(cs, origin: client.host) { req.setValue(auth, forHTTPHeaderField: "Authorization") }

        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw LiMusicError(message: "YouTube antwortet mit Fehler \(h.statusCode)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LiMusicError(message: "Antwort von YouTube nicht lesbar")
        }
        return obj
    }

    /// „Gefällt mir“ mit dem YouTube-Konto abgleichen
    func setLike(videoId: String, liked: Bool, music: Bool) async {
        guard await isLoggedIn() else { return }
        _ = try? await call(liked ? "like/like" : "like/removelike", client: music ? .music : .web,
                            body: ["target": ["videoId": videoId]])
    }

    /// Kanal abonnieren / Abo beenden (braucht Anmeldung)
    func setSubscribed(channelId: String, _ on: Bool) async throws {
        _ = try await call(on ? "subscription/subscribe" : "subscription/unsubscribe", client: .web,
                           body: ["channelIds": [channelId]])
    }

    /// Alles zum laufenden Video: Aufrufe, Likes, Beschreibung, Kapitel, Kanal, Kommentar-Schlüssel
    func videoDetails(videoId: String) async -> VideoDetails? {
        guard let n = try? await next(videoId: videoId, playlistId: nil, client: .web) else { return nil }
        var d = VideoDetails()
        let primary = Parser.findValue(n, key: "videoPrimaryInfoRenderer") as? [String: Any]
        if let vr = Parser.findValue(primary, key: "videoViewCountRenderer") as? [String: Any] {
            d.views = Parser.text(vr["viewCount"])
        }
        d.date = Parser.text(primary?["dateText"])
        if let lb = Parser.findValue(primary, key: "defaultButtonViewModel") as? [String: Any],
           let t = Parser.findValue(lb, key: "title") as? String {
            d.likes = t
        }
        if let s = Parser.findValue(primary, key: "likeStatus") as? String,
           let ls = VideoDetails.LikeStatus(rawValue: s) {
            d.likeStatus = ls
        }
        let secondary = Parser.findValue(n, key: "videoSecondaryInfoRenderer") as? [String: Any]
        if let c = (secondary?["attributedDescription"] as? [String: Any])?["content"] as? String {
            d.description = c
        } else {
            d.description = Parser.text(secondary?["description"])
        }

        let owner = Parser.findValue(n, key: "videoOwnerRenderer") as? [String: Any]
        d.channelName = Parser.text(owner?["title"])
        if let sb = Parser.findValue(n, key: "subscribeButtonRenderer") as? [String: Any],
           let cid = sb["channelId"] as? String {
            d.channelId = cid
            d.subscribed = (sb["subscribed"] as? Bool) ?? false
        } else {
            var ids: [String] = []
            Parser.collectStrings(owner, key: "browseId", into: &ids)
            d.channelId = ids.first { $0.hasPrefix("UC") }
            let state = Parser.findValue(n, key: "subscriptionStateEntity") as? [String: Any]
            d.subscribed = (state?["subscribed"] as? Bool) ?? false
        }

        if let mm = Parser.findValue(n, key: "macroMarkersListRenderer") as? [String: Any],
           let cs = mm["contents"] as? [[String: Any]] {
            for (i, c) in cs.enumerated() {
                guard let it = c["macroMarkersListItemRenderer"] as? [String: Any] else { continue }
                let start = (Parser.findValue(it["onTap"], key: "startTimeSeconds") as? NSNumber)?.doubleValue ?? 0
                d.chapters.append(Chapter(id: i, title: Parser.text(it["title"]),
                                          time: Parser.text(it["timeDescription"]), start: start))
            }
        }
        d.commentsToken = Parser.commentsToken(n)
        return d
    }

    /// Daumen hoch/runter: "like", "dislike" oder "removelike"
    func rate(videoId: String, _ action: String) async throws {
        _ = try await call("like/\(action)", client: .web, body: ["target": ["videoId": videoId]])
    }

    func addToPlaylist(_ playlistId: String, videoId: String) async throws {
        _ = try await call("browse/edit_playlist", client: .web,
                           body: ["playlistId": playlistId,
                                  "actions": [["action": "ACTION_ADD_VIDEO", "addedVideoId": videoId]]])
    }

    func feedback(_ token: String) async {
        _ = try? await call("feedback", client: .web, body: ["feedbackTokens": [token]])
    }

    func comments(token: String) async throws -> (comments: [Comment], next: String?) {
        let r = try await call("next", client: .web, body: ["continuation": token])
        return (Parser.comments(r), Parser.continuationToken(r))
    }

    func channelSubscribed(_ channelId: String) async -> Bool {
        guard let r = try? await browse(channelId, client: .web) else { return false }
        if let sb = Parser.findValue(r, key: "subscribeButtonRenderer") as? [String: Any] {
            return (sb["subscribed"] as? Bool) ?? false
        }
        let state = Parser.findValue(r, key: "subscriptionStateEntity") as? [String: Any]
        return (state?["subscribed"] as? Bool) ?? false
    }

    func browse(_ id: String, client: Client, params: String? = nil) async throws -> [String: Any] {
        var b: [String: Any] = ["browseId": id]
        if let p = params { b["params"] = p }
        return try await call("browse", client: client, body: b)
    }

    func browseContinuation(_ token: String, client: Client) async throws -> [String: Any] {
        if client == .web {
            return try await call("browse", client: client, body: ["continuation": token])
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        let t = token.addingPercentEncoding(withAllowedCharacters: allowed) ?? token
        return try await call("browse", client: client, body: ["continuation": token],
                              query: "&ctoken=\(t)&continuation=\(t)&type=next")
    }

    func search(_ q: String, client: Client, params: String? = nil) async throws -> [String: Any] {
        var b: [String: Any] = ["query": q]
        if let p = params { b["params"] = p }
        return try await call("search", client: client, body: b)
    }

    func next(videoId: String, playlistId: String?, client: Client) async throws -> [String: Any] {
        var b: [String: Any] = ["videoId": videoId]
        if let p = playlistId { b["playlistId"] = p }
        if client == .music { b["isAudioOnly"] = true }
        return try await call("next", client: client, body: b)
    }
}
