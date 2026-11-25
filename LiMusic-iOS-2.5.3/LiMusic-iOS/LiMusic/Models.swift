import Foundation

enum AppMode: String {
    case video, music
}

struct MediaItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case video(String)
        case collection(String)   // browseId
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    var thumbnail: URL?
    let duration: String?
    let progress: Double?
    let isMusic: Bool
    var hasVideo: Bool = false
    var artistId: String? = nil
    var isShort: Bool = false
    var feedbackToken: String? = nil

    var videoId: String? {
        if case .video(let v) = kind { return v }
        return nil
    }

    var browseId: String? {
        if case .collection(let b) = kind { return b }
        return nil
    }
}

struct Shelf: Identifiable, Hashable {
    enum Style { case featured, carousel, list, grid, shorts }

    let id = UUID()
    let title: String
    var items: [MediaItem]
    var style: Style = .carousel
    var limit: Int? = nil
    var isHistory = false
    /// Antippen startet ein Radio im Stil des Titels statt die Liste abzuspielen
    var radio = false

    static func == (a: Shelf, b: Shelf) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum Route: Hashable {
    case local(UUID?)          // eigene Playlist (nil = „Gefällt mir“)
    case search(String, AppMode)
    case collection(MediaItem)
    case shelf(Shelf)
}

struct ClassicPage: Identifiable {
    let id = UUID()
    let url: URL
}

enum FeedKind: String {
    case home, explore, library
}

struct LiMusicError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Filter-Reiter für die Musik-Suche
enum MusicFilter: String, CaseIterable, Identifiable {
    case all, songs, videos, albums, artists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Alle"
        case .songs: return "Titel"
        case .videos: return "Videos"
        case .albums: return "Alben"
        case .artists: return "Interpreten"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .songs: return "music.note"
        case .videos: return "play.rectangle.fill"
        case .albums: return "square.stack.fill"
        case .artists: return "person.fill"
        }
    }

    /// Filter-Parameter der YouTube-Music-Suche
    var params: String? {
        let tail = "AWoMEA4QChADEAQQCRAF"
        switch self {
        case .all: return nil
        case .songs: return "EgWKAQII" + tail
        case .videos: return "EgWKAQIQ" + tail
        case .albums: return "EgWKAQIY" + tail
        case .artists: return "EgWKAQIg" + tail
        }
    }
}

extension MediaItem {
    /// Interpreten-Seite (Kanal) in YouTube Music
    var isArtist: Bool { isMusic && (browseId?.hasPrefix("UC") ?? false) }

    /// Name des Interpreten, aus der Unterzeile geraten
    var artistName: String? {
        let skip: Set<String> = ["titel", "song", "video", "album", "single", "ep", "playlist", "interpret", "künstler", "mix"]
        for part in subtitle.components(separatedBy: " • ") {
            let t = part.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || skip.contains(t.lowercased()) { continue }
            if t.first?.isNumber == true { continue }
            return t
        }
        return nil
    }
}

enum RecentSearches {
    private static let key = "recentSearches"

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ q: String) -> [String] {
        var list = load().filter { $0.lowercased() != q.lowercased() }
        list.insert(q, at: 0)
        list = Array(list.prefix(10))
        UserDefaults.standard.set(list, forKey: key)
        return list
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Gespeicherter Titel (für eigene Playlists und „Gefällt mir“)
struct SavedTrack: Codable, Hashable {
    let videoId: String
    let title: String
    let subtitle: String
    let thumbnail: String?
    let isMusic: Bool
    let hasVideo: Bool
    let artistId: String?

    init(_ m: MediaItem) {
        videoId = m.videoId ?? ""
        title = m.title
        subtitle = m.subtitle
        thumbnail = m.thumbnail?.absoluteString
        isMusic = m.isMusic
        hasVideo = m.hasVideo
        artistId = m.artistId
    }

    var item: MediaItem {
        MediaItem(id: "v:\(videoId)", kind: .video(videoId), title: title, subtitle: subtitle,
                  thumbnail: thumbnail.flatMap { URL(string: $0) }, duration: nil, progress: nil,
                  isMusic: isMusic, hasVideo: hasVideo, artistId: artistId)
    }
}

struct LocalPlaylist: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var tracks: [SavedTrack]
}

extension MediaItem {
    /// Navigation zur Interpreten-Seite, wenn YouTube Music eine ID mitliefert
    var artistRoute: Route? {
        guard let aid = artistId else { return nil }
        let stub = MediaItem(id: "c:\(aid)", kind: .collection(aid), title: artistName ?? "Interpret",
                             subtitle: "Interpret", thumbnail: nil, duration: nil, progress: nil, isMusic: true)
        return .collection(stub)
    }
}

extension MediaItem {
    /// Kanal- oder Interpreten-Seite (runde Kachel)
    var isChannel: Bool { browseId?.hasPrefix("UC") ?? false }
}

/// Filter-Reiter für die Video-Suche
enum VideoFilter: String, CaseIterable, Identifiable {
    case all, videos, channels, playlists, newest, today, week, short, long

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Alle"
        case .videos: return "Videos"
        case .channels: return "Kanäle"
        case .playlists: return "Playlists"
        case .newest: return "Neueste"
        case .today: return "Heute"
        case .week: return "Diese Woche"
        case .short: return "Kurz"
        case .long: return "Lang"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .videos: return "play.rectangle.fill"
        case .channels: return "person.crop.circle.fill"
        case .playlists: return "list.bullet.rectangle.fill"
        case .newest: return "arrow.down.circle.fill"
        case .today: return "sun.max.fill"
        case .week: return "calendar"
        case .short: return "hare.fill"
        case .long: return "tortoise.fill"
        }
    }

    /// Filter-Parameter der YouTube-Suche
    var params: String? {
        switch self {
        case .all: return nil
        case .videos: return "EgIQAQ=="
        case .channels: return "EgIQAg=="
        case .playlists: return "EgIQAw=="
        case .newest: return "CAI="
        case .today: return "EgIIAg=="
        case .week: return "EgIIAw=="
        case .short: return "EgIYAQ=="
        case .long: return "EgIYAg=="
        }
    }
}

struct Chapter: Identifiable, Equatable {
    let id: Int
    let title: String
    let time: String
    let start: Double
}

struct Comment: Identifiable, Equatable {
    let id: String
    let author: String
    let text: String
    let time: String
    let likes: String
    let avatar: URL?
    let replies: String
}

/// Angaben zum laufenden Video (Aufrufe, Likes, Beschreibung, Kapitel, Kanal)
struct VideoDetails: Equatable {
    enum LikeStatus: String { case like = "LIKE", dislike = "DISLIKE", none = "INDIFFERENT" }

    var views = ""
    var date = ""
    var likes = ""
    var description = ""
    var likeStatus: LikeStatus = .none
    var chapters: [Chapter] = []
    var commentsToken: String?
    var channelId: String?
    var channelName = ""
    var subscribed = false
}
