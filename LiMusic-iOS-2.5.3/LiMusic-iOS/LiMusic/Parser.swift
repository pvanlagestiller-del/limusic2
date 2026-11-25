import Foundation

/// Liest YouTube-Antworten robust aus: sucht bekannte "Renderer" an beliebiger Stelle im JSON,
/// damit kleine Umbauten bei YouTube nicht sofort alles kaputt machen.
enum Parser {
    typealias J = [String: Any]

    static let itemKeys: Set<String> = [
        "videoRenderer", "compactVideoRenderer", "gridVideoRenderer", "playlistVideoRenderer",
        "playlistPanelVideoRenderer", "videoWithContextRenderer", "lockupViewModel",
        "musicResponsiveListItemRenderer", "musicTwoRowItemRenderer",
        "gridPlaylistRenderer", "playlistRenderer", "compactPlaylistRenderer",
        "shortsLockupViewModel", "reelItemRenderer", "channelRenderer", "gridChannelRenderer"
    ]

    static let shelfKeys: Set<String> = [
        "musicCarouselShelfRenderer", "musicShelfRenderer", "musicPlaylistShelfRenderer",
        "musicImmersiveCarouselShelfRenderer", "richShelfRenderer", "shelfRenderer",
        "horizontalCardListRenderer", "reelShelfRenderer"
    ]

    static let skipKeys: Set<String> = [
        "responseContext", "frameworkUpdates", "topbar", "adSlotRenderer", "trackingParams", "microformat",
        "musicCardShelfRenderer", "statementBannerRenderer", "brandVideoSingletonRenderer"
    ]

    // MARK: Text / Bilder

    static func text(_ v: Any?) -> String {
        if let s = v as? String { return s }
        guard let o = v as? J else { return "" }
        if let s = o["simpleText"] as? String { return s }
        if let runs = o["runs"] as? [J] { return runs.compactMap { $0["text"] as? String }.joined() }
        if let s = o["content"] as? String { return s }
        return ""
    }

    /// Größtes echtes Vorschaubild. Sammelt alle Bildlisten und nimmt nur Einträge mit Adresse –
    /// Symbol-Listen (z. B. Badge-Icons ohne url) werden ignoriert.
    static func bestThumb(_ v: Any?) -> URL? {
        var candidates: [J] = []
        collectImages(v, into: &candidates)
        let best = candidates.max { (($0["width"] as? Int) ?? 0) < (($1["width"] as? Int) ?? 0) }
        guard var s = best?["url"] as? String else { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        return URL(string: s)
    }

    private static func collectImages(_ v: Any?, into out: inout [J], depth: Int = 0) {
        guard depth < 14 else { return }
        if let o = v as? J {
            for (k, child) in o {
                if (k == "thumbnails" || k == "sources"), let arr = child as? [J] {
                    out += arr.filter { ($0["url"] as? String).map { $0.hasPrefix("http") || $0.hasPrefix("//") } ?? false }
                } else {
                    collectImages(child, into: &out, depth: depth + 1)
                }
            }
        } else if let a = v as? [Any] {
            for child in a { collectImages(child, into: &out, depth: depth + 1) }
        }
    }

    static func findArray(_ v: Any?, keys: [String], depth: Int = 0) -> [J]? {
        guard depth < 10 else { return nil }
        if let o = v as? J {
            for k in keys { if let a = o[k] as? [J], !a.isEmpty { return a } }
            for (_, child) in o {
                if let r = findArray(child, keys: keys, depth: depth + 1) { return r }
            }
        } else if let a = v as? [Any] {
            for child in a {
                if let r = findArray(child, keys: keys, depth: depth + 1) { return r }
            }
        }
        return nil
    }

    static func findValue(_ v: Any?, key: String, depth: Int = 0) -> Any? {
        guard depth < 14 else { return nil }
        if let o = v as? J {
            if let r = o[key] { return r }
            for (_, child) in o {
                if let r = findValue(child, key: key, depth: depth + 1) { return r }
            }
        } else if let a = v as? [Any] {
            for child in a {
                if let r = findValue(child, key: key, depth: depth + 1) { return r }
            }
        }
        return nil
    }

    static func collectStrings(_ v: Any?, key: String, into out: inout [String], depth: Int = 0) {
        guard depth < 14 else { return }
        if let o = v as? J {
            for (k, child) in o {
                if k == key, let s = child as? String { out.append(s) } else {
                    collectStrings(child, key: key, into: &out, depth: depth + 1)
                }
            }
        } else if let a = v as? [Any] {
            for child in a { collectStrings(child, key: key, into: &out, depth: depth + 1) }
        }
    }

    private static func join(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private static func percent(_ v: Any?) -> Double? {
        if let i = v as? Int { return Double(i) / 100 }
        if let d = v as? Double { return d / 100 }
        return nil
    }

    // MARK: Einzelne Einträge

    static func item(key: String, _ r: J, music: Bool) -> MediaItem? {
        guard var it = itemRaw(key: key, r, music: music) else { return nil }
        if !music, it.videoId != nil {
            it.feedbackToken = findValue(r, key: "feedbackToken") as? String
        }
        if it.thumbnail == nil, let vid = it.videoId {
            it.thumbnail = URL(string: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg")
        }
        if music, it.browseId?.hasPrefix("UC") != true {
            var ids: [String] = []
            collectStrings(r["flexColumns"] ?? r["subtitle"], key: "browseId", into: &ids)
            it.artistId = ids.first { $0.hasPrefix("UC") }
        }
        return it
    }

    static func itemRaw(key: String, _ r: J, music: Bool) -> MediaItem? {
        switch key {
        case "videoRenderer", "compactVideoRenderer", "gridVideoRenderer", "playlistVideoRenderer",
             "playlistPanelVideoRenderer", "videoWithContextRenderer":
            guard let vid = r["videoId"] as? String else { return nil }
            let title = text(r["title"]).isEmpty ? text(r["headline"]) : text(r["title"])
            let owner = [r["ownerText"], r["shortBylineText"], r["longBylineText"]]
                .map { text($0) }.first { !$0.isEmpty } ?? ""
            let views = text(r["shortViewCountText"]).isEmpty ? text(r["viewCountText"]) : text(r["shortViewCountText"])
            var duration = text(r["lengthText"])
            if duration.isEmpty, let o = findValue(r["thumbnailOverlays"], key: "thumbnailOverlayTimeStatusRenderer") as? J {
                duration = text(o["text"])
            }
            return MediaItem(id: "v:\(vid)", kind: .video(vid), title: title,
                             subtitle: join([owner, views, text(r["publishedTimeText"])]),
                             thumbnail: bestThumb(r["thumbnail"]),
                             duration: duration.isEmpty ? nil : duration,
                             progress: percent(findValue(r["thumbnailOverlays"], key: "percentDurationWatched")),
                             isMusic: music)

        case "lockupViewModel":
            guard let cid = r["contentId"] as? String else { return nil }
            let type = (r["contentType"] as? String) ?? ""
            let meta = (r["metadata"] as? J)?["lockupMetadataViewModel"] as? J
            let title = text(meta?["title"])
            var parts: [String] = []
            collectStrings(meta?["metadata"], key: "content", into: &parts)
            var badge: String?
            if let b = findValue(r["contentImage"], key: "thumbnailBadgeViewModel") as? J {
                badge = b["text"] as? String
            }
            let progress = percent(findValue(r["contentImage"], key: "startPercent"))
            let thumb = bestThumb(r["contentImage"])
            // „Mix“ (RD…) ist ein Radio ab einem Video -> direkt abspielbar
            if cid.hasPrefix("RD"),
               let vid = (findValue(r["rendererContext"], key: "videoId") as? String)
                    ?? (cid.count == 13 ? String(cid.dropFirst(2)) : nil) {
                return MediaItem(id: "v:\(vid)", kind: .video(vid), title: title, subtitle: join(parts),
                                 thumbnail: thumb, duration: badge, progress: nil, isMusic: music)
            }
            if type.contains("PLAYLIST") || type.contains("ALBUM") {
                return MediaItem(id: "c:\(cid)", kind: .collection(cid.hasPrefix("VL") ? cid : "VL\(cid)"),
                                 title: title, subtitle: join(parts), thumbnail: thumb,
                                 duration: badge, progress: nil, isMusic: music)
            }
            guard type.isEmpty || type.contains("VIDEO") else { return nil }
            return MediaItem(id: "v:\(cid)", kind: .video(cid), title: title, subtitle: join(parts),
                             thumbnail: thumb, duration: badge, progress: progress, isMusic: music)

        case "musicResponsiveListItemRenderer":
            var cols: [String] = []
            for c in (r["flexColumns"] as? [J]) ?? [] {
                let t = text((c["musicResponsiveListItemFlexColumnRenderer"] as? J)?["text"])
                if !t.isEmpty { cols.append(t) }
            }
            let title = cols.first ?? ""
            let sub = join(Array(cols.dropFirst()))
            var duration: String?
            if let fc = (r["fixedColumns"] as? [J])?.first,
               let fr = fc["musicResponsiveListItemFixedColumnRenderer"] as? J {
                let t = text(fr["text"]); if !t.isEmpty { duration = t }
            }
            let thumb = bestThumb(r["thumbnail"])
            if let vid = (findValue(r["playlistItemData"], key: "videoId") ?? findValue(r["overlay"], key: "videoId")) as? String {
                return MediaItem(id: "v:\(vid)", kind: .video(vid), title: title, subtitle: sub,
                                 thumbnail: thumb, duration: duration, progress: nil, isMusic: true,
                                 hasVideo: isMusicVideo(r))
            }
            if let bid = findValue(r["navigationEndpoint"], key: "browseId") as? String {
                return MediaItem(id: "c:\(bid)", kind: .collection(bid), title: title, subtitle: sub,
                                 thumbnail: thumb, duration: nil, progress: nil, isMusic: true)
            }
            return nil

        case "musicTwoRowItemRenderer":
            let title = text(r["title"])
            let sub = text(r["subtitle"])
            let thumb = bestThumb(r["thumbnailRenderer"])
            let nav = r["navigationEndpoint"] as? J
            if let vid = findValue(nav?["watchEndpoint"], key: "videoId") as? String {
                return MediaItem(id: "v:\(vid)", kind: .video(vid), title: title, subtitle: sub,
                                 thumbnail: thumb, duration: nil, progress: nil, isMusic: true,
                                 hasVideo: isMusicVideo(r))
            }
            if let bid = findValue(nav, key: "browseId") as? String {
                return MediaItem(id: "c:\(bid)", kind: .collection(bid), title: title, subtitle: sub,
                                 thumbnail: thumb, duration: nil, progress: nil, isMusic: true)
            }
            return nil

        case "channelRenderer", "gridChannelRenderer":
            guard let cid = r["channelId"] as? String else { return nil }
            return MediaItem(id: "c:\(cid)", kind: .collection(cid), title: text(r["title"]),
                             subtitle: join([text(r["subscriberCountText"]), text(r["videoCountText"])]),
                             thumbnail: bestThumb(r["thumbnail"]), duration: nil, progress: nil, isMusic: false)

        case "shortsLockupViewModel":
            var vid = (findValue(r["onTap"], key: "reelWatchEndpoint") as? J)?["videoId"] as? String
            if vid == nil, let e = r["entityId"] as? String, e.hasPrefix("shorts-shelf-item-") {
                vid = String(e.dropFirst("shorts-shelf-item-".count))
            }
            guard let vid else { return nil }
            let meta = r["overlayMetadata"] as? J
            let title = text((meta?["primaryText"] as? J)?["content"] ?? r["accessibilityText"])
            let views = text((meta?["secondaryText"] as? J)?["content"])
            return MediaItem(id: "v:\(vid)", kind: .video(vid), title: title, subtitle: views,
                             thumbnail: bestThumb(r["thumbnail"]) ?? bestThumb(r), duration: nil, progress: nil,
                             isMusic: false, isShort: true)

        case "reelItemRenderer":
            guard let vid = r["videoId"] as? String else { return nil }
            return MediaItem(id: "v:\(vid)", kind: .video(vid), title: text(r["headline"]),
                             subtitle: text(r["viewCountText"]), thumbnail: bestThumb(r["thumbnail"]),
                             duration: nil, progress: nil, isMusic: false, isShort: true)

        case "gridPlaylistRenderer", "playlistRenderer", "compactPlaylistRenderer":
            guard let pid = r["playlistId"] as? String else { return nil }
            return MediaItem(id: "c:VL\(pid)", kind: .collection("VL\(pid)"), title: text(r["title"]),
                             subtitle: join([text(r["shortBylineText"]), text(r["videoCountText"])]),
                             thumbnail: bestThumb(r["thumbnail"] ?? r["thumbnails"]),
                             duration: nil, progress: nil, isMusic: music)
        default:
            return nil
        }
    }

    // MARK: Sammeln

    static func collectItems(_ v: Any, music: Bool, into out: inout [MediaItem], depth: Int = 0) {
        guard depth < 40 else { return }
        if let o = v as? J {
            for (k, child) in o {
                if skipKeys.contains(k) { continue }
                if itemKeys.contains(k), let r = child as? J {
                    if let it = item(key: k, r, music: music) { out.append(it) }
                    continue
                }
                collectItems(child, music: music, into: &out, depth: depth + 1)
            }
        } else if let a = v as? [Any] {
            for child in a { collectItems(child, music: music, into: &out, depth: depth + 1) }
        }
    }

    static func shelfTitle(_ r: J) -> String {
        let t = text(r["title"])
        if !t.isEmpty { return t }
        if let h = r["header"] { return text(findValue(h, key: "title")) }
        return ""
    }

    static func dedupe(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { !$0.title.isEmpty && seen.insert($0.id).inserted }
    }

    /// Regale (mit Titel) und lose Einträge (z. B. Empfehlungsraster), in Reihenfolge.
    static func shelves(_ root: Any, music: Bool) -> (shelves: [Shelf], loose: [MediaItem]) {
        var result: [Shelf] = []
        var loose: [MediaItem] = []

        func walk(_ v: Any, depth: Int) {
            guard depth < 40 else { return }
            if let o = v as? J {
                for (k, child) in o {
                    if skipKeys.contains(k) { continue }
                    if itemKeys.contains(k), let r = child as? J {
                        if let it = item(key: k, r, music: music) { loose.append(it) }
                        continue
                    }
                    if shelfKeys.contains(k), let r = child as? J {
                        var items: [MediaItem] = []
                        collectItems(r, music: music, into: &items)
                        let clean = dedupe(items)
                        if !clean.isEmpty {
                            let shorts = clean.allSatisfy { $0.isShort }
                            result.append(Shelf(title: shorts && shelfTitle(r).isEmpty ? "Shorts" : shelfTitle(r),
                                                items: clean, style: shorts ? .shorts : .carousel))
                        }
                        continue
                    }
                    walk(child, depth: depth + 1)
                }
            } else if let a = v as? [Any] {
                for child in a { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return (result, dedupe(loose))
    }

    /// true, wenn YouTube Music den Eintrag als echtes Musikvideo kennzeichnet
    static func isMusicVideo(_ r: Any?) -> Bool {
        guard let t = findValue(r, key: "musicVideoType") as? String else { return false }
        return t.contains("OMV") || t.contains("UGC") || t.contains("OFFICIAL_SOURCE")
    }

    static func allItems(_ root: Any, music: Bool) -> [MediaItem] {
        var out: [MediaItem] = []
        collectItems(root, music: music, into: &out)
        return dedupe(out)
    }

    // MARK: Fortsetzung (Endlos-Scrollen)

    static func continuationToken(_ root: Any) -> String? {
        // YouTube Music: nextContinuationData an der Hauptliste
        for key in ["sectionListContinuation", "sectionListRenderer"] {
            if let sl = findValue(root, key: key) as? J,
               let conts = sl["continuations"] as? [J],
               let c = (conts.first?["nextContinuationData"] as? J)?["continuation"] as? String {
                return c
            }
        }
        // YouTube: continuationItemRenderer am Ende der längsten Liste
        var best: (count: Int, token: String)?
        func walk(_ v: Any, depth: Int) {
            guard depth < 40 else { return }
            if let a = v as? [Any] {
                if let last = a.last as? J, let cir = last["continuationItemRenderer"] as? J,
                   let tok = (findValue(cir, key: "continuationCommand") as? J)?["token"] as? String,
                   a.count > (best?.count ?? 0) {
                    best = (a.count, tok)
                }
                for x in a { walk(x, depth: depth + 1) }
            } else if let o = v as? J {
                for (_, c) in o { walk(c, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return best?.token
    }

    // MARK: Kommentare

    static func commentsToken(_ root: Any) -> String? {
        var result: String?
        func walk(_ v: Any, depth: Int) {
            guard depth < 30, result == nil else { return }
            if let o = v as? J {
                if (o["sectionIdentifier"] as? String) == "comment-item-section" {
                    result = (findValue(o, key: "continuationCommand") as? J)?["token"] as? String
                    return
                }
                for (_, c) in o { walk(c, depth: depth + 1) }
            } else if let a = v as? [Any] {
                for c in a { walk(c, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return result
    }

    static func comments(_ root: Any) -> [Comment] {
        var out: [Comment] = []
        func walk(_ v: Any, depth: Int) {
            guard depth < 40 else { return }
            if let o = v as? J {
                if let p = o["commentEntityPayload"] as? J {
                    let props = p["properties"] as? J
                    let author = p["author"] as? J
                    let tb = p["toolbar"] as? J
                    let txt = ((props?["content"] as? J)?["content"] as? String) ?? ""
                    if !txt.isEmpty {
                        out.append(Comment(
                            id: (props?["commentId"] as? String) ?? UUID().uuidString,
                            author: (author?["displayName"] as? String) ?? "",
                            text: txt,
                            time: (props?["publishedTime"] as? String) ?? "",
                            likes: (tb?["likeCountNotliked"] as? String) ?? "",
                            avatar: (author?["avatarThumbnailUrl"] as? String).flatMap { URL(string: $0) },
                            replies: (tb?["replyCount"] as? String) ?? ""))
                    }
                    return
                }
                if let c = o["commentRenderer"] as? J {
                    let txt = text(c["contentText"])
                    if !txt.isEmpty {
                        out.append(Comment(
                            id: (c["commentId"] as? String) ?? UUID().uuidString,
                            author: text(c["authorText"]),
                            text: txt,
                            time: text(c["publishedTimeText"]),
                            likes: text(c["voteCount"]),
                            avatar: bestThumb(c["authorThumbnail"]),
                            replies: ""))
                    }
                    return
                }
                for (_, c) in o { walk(c, depth: depth + 1) }
            } else if let a = v as? [Any] {
                for c in a { walk(c, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }

    /// „Top-Ergebnis“-Karte der YouTube-Music-Suche
    static func topResult(_ root: Any) -> MediaItem? {
        guard let c = findValue(root, key: "musicCardShelfRenderer") as? J else { return nil }
        let title = text(c["title"])
        guard !title.isEmpty else { return nil }
        let sub = text(c["subtitle"])
        let thumb = bestThumb(c["thumbnail"])
        var ids: [String] = []
        collectStrings(c["subtitle"], key: "browseId", into: &ids)
        let artist = ids.first { $0.hasPrefix("UC") }
        let nav = c["title"] ?? c["onTap"]
        if let vid = (findValue(nav, key: "videoId") ?? findValue(c["onTap"], key: "videoId")) as? String {
            return MediaItem(id: "v:\(vid)", kind: .video(vid), title: title, subtitle: sub, thumbnail: thumb,
                             duration: nil, progress: nil, isMusic: true, hasVideo: isMusicVideo(c), artistId: artist)
        }
        if let bid = (findValue(nav, key: "browseId") ?? findValue(c["onTap"], key: "browseId")) as? String {
            return MediaItem(id: "c:\(bid)", kind: .collection(bid), title: title, subtitle: sub, thumbnail: thumb,
                             duration: nil, progress: nil, isMusic: true)
        }
        return nil
    }
}
