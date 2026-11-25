import SwiftUI

// MARK: Vorschaubild

struct Thumb: View {
    let url: URL?
    var ratio: CGFloat = 16 / 9
    var corner: CGFloat = 12

    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay(
                RemoteImage(url: url)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct PlayBadge: View {
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Color.black.opacity(0.45))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.25)))
    }
}

struct DurationBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ProgressLine: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.25))
                Rectangle().fill(Theme.accent).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 3)
    }
}

// MARK: Karten

struct FeaturedCard: View {
    let item: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Thumb(url: item.thumbnail, corner: 18)
                .overlay(PlayBadge(size: 56))
                .overlay(alignment: .bottomTrailing) {
                    if let d = item.duration { DurationBadge(text: d).padding(10) }
                }
                .overlay(alignment: .bottom) {
                    if let p = item.progress { ProgressLine(value: p) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke))
                .glow(radius: 18, opacity: 0.22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text2)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct VideoCard: View {
    let item: MediaItem
    var fluid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumb(url: item.thumbnail, corner: 12)
                .overlay(PlayBadge(size: 36))
                .overlay(alignment: .bottomTrailing) {
                    if let d = item.duration { DurationBadge(text: d).padding(6) }
                }
                .overlay(alignment: .bottom) {
                    if let p = item.progress { ProgressLine(value: p) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text2)
                    .lineLimit(1)
            }
        }
        .frame(width: fluid ? nil : 190, alignment: .leading)
        .frame(maxWidth: fluid ? .infinity : nil, alignment: .leading)
    }
}

struct MusicCard: View {
    let item: MediaItem
    var fluid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumb(url: item.thumbnail, ratio: 1, corner: item.isChannel ? 999 : 14)
                .overlay(alignment: .bottomTrailing) {
                    if item.videoId != nil { PlayBadge(size: 34).padding(8) }
                }
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text2)
                    .lineLimit(1)
            }
        }
        .frame(width: fluid ? nil : 156, alignment: .leading)
        .frame(maxWidth: fluid ? .infinity : nil, alignment: .leading)
    }
}

struct ShortCard: View {
    let item: MediaItem
    var fluid = false

    var body: some View {
        Thumb(url: item.thumbnail, ratio: 9 / 16, corner: 14)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Theme.accent)
                    .clipShape(Circle())
                    .padding(8)
            }
            .frame(width: fluid ? nil : 132)
            .frame(maxWidth: fluid ? .infinity : nil)
    }
}

struct ListRow: View {
    let item: MediaItem
    var isCurrent = false
    var body: some View {
        HStack(spacing: 12) {
            Thumb(url: item.thumbnail, ratio: (item.isMusic || item.isChannel) ? 1 : 16 / 9, corner: item.isChannel ? 999 : 8)
                .frame(width: (item.isMusic || item.isChannel) ? 54 : 96)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isCurrent ? Theme.accent : Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let d = item.duration {
                Text(d).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.text2)
            } else if item.videoId == nil {
                Image(systemName: "chevron.right").foregroundColor(Theme.text2)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: Regal

struct ShelfView: View {
    let shelf: Shelf
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var session: SessionState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !shelf.title.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(shelf.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    if hasMore {
                        NavigationLink(value: Route.shelf(shelf)) {
                            HStack(spacing: 3) {
                                Text("Alle")
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.accent)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            switch shelf.style {
            case .featured:
                ForEach(visible) { item in tile(item) { FeaturedCard(item: item) } }
                    .padding(.horizontal, 16)
            case .carousel:
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(visible) { item in
                            tile(item) {
                                if item.isMusic || item.isChannel { MusicCard(item: item) } else { VideoCard(item: item) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            case .shorts:
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(visible) { item in
                            tile(item) { ShortCard(item: item) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            case .grid:
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                          alignment: .leading, spacing: 18) {
                    ForEach(gridItems) { item in
                        tile(item) {
                            if item.isShort {
                                ShortCard(item: item, fluid: true)
                            } else if item.isMusic || item.isChannel {
                                MusicCard(item: item, fluid: true)
                            } else {
                                VideoCard(item: item, fluid: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            case .list:
                LazyVStack(spacing: 16) {
                    ForEach(visible) { item in
                        tile(item) {
                            if item.isMusic || item.videoId == nil {
                                ListRow(item: item, isCurrent: player.current?.id == item.id)
                            } else {
                                FeaturedCard(item: item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var visible: [MediaItem] {
        session.hidden.isEmpty ? shelf.items : shelf.items.filter { !session.hidden.contains($0.id) }
    }

    private var gridItems: [MediaItem] {
        if let l = shelf.limit { return Array(visible.prefix(l)) }
        return visible
    }

    private var hasMore: Bool {
        if shelf.style == .carousel || shelf.style == .shorts { return shelf.items.count > 4 }
        if let l = shelf.limit { return shelf.items.count > l }
        return false
    }

    @ViewBuilder
    private func tile<Content: View>(_ item: MediaItem, @ViewBuilder content: () -> Content) -> some View {
        if item.videoId != nil {
            Button {
                if shelf.radio { player.playRadio(item) } else { player.play(item, in: visible) }
            } label: {
                content()
            }
            .buttonStyle(PressStyle())
            .contextMenu {
                Button { player.playNext(item) } label: {
                    Label("Als Nächstes spielen", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button { player.enqueue(item) } label: {
                    Label("Zur Warteschlange", systemImage: "text.badge.plus")
                }
                if shelf.isHistory, let token = item.feedbackToken {
                    Button(role: .destructive) {
                        session.hidden.insert(item.id)
                        Feeds.clearCache()
                        Task { await InnerTube.shared.feedback(token) }
                    } label: {
                        Label("Aus Verlauf entfernen", systemImage: "trash")
                    }
                }
                Button { LocalLibrary.shared.toggleLike(item) } label: {
                    if LocalLibrary.shared.isLiked(item) {
                        Label("Gefällt mir nicht mehr", systemImage: "heart.slash")
                    } else {
                        Label("Gefällt mir", systemImage: "heart")
                    }
                }
                PlaylistMenu(item: item) {
                    Label("Zur Playlist", systemImage: "music.note.list")
                }
                if let route = item.artistRoute {
                    Button { session.pendingRoute = route } label: {
                        Label("Zum Interpreten", systemImage: "person.fill")
                    }
                } else if let artist = item.artistName {
                    Button { session.pendingSearch = artist } label: {
                        Label("Zum Interpreten", systemImage: "person.fill")
                    }
                }
            }
        } else {
            NavigationLink(value: Route.collection(item)) {
                content()
            }
            .buttonStyle(PressStyle())
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: Kopfbereich

struct TopArea: View {
    @Binding var mode: AppMode
    let onSearch: (String) -> Void
    @State private var query = ""
    @State private var suggestions: [String] = []
    @State private var recents: [String] = RecentSearches.load()
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showingRecents: Bool { trimmed.isEmpty }
    private var rows: [String] { showingRecents ? recents : suggestions }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .glow(radius: 10, opacity: 0.55)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LiMusic")
                        .font(.system(size: 27, weight: .bold))
                    Text("Videos • Musik • Alles in einem")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text2)
                }
                Spacer()
                AirPlayButton().frame(width: 34, height: 34)
            }

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                TextField("", text: $query,
                          prompt: Text(mode == .video ? "Videos, Kanäle suchen …" : "Musik, Künstler, Alben suchen …")
                            .foregroundColor(Theme.text2))
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .onSubmit { submit(query) }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Theme.text2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Theme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(focused ? Theme.accent.opacity(0.7) : Theme.stroke))

            if focused && !rows.isEmpty {
                suggestionList
            }

            ModeSwitcher(mode: $mode)
        }
        .foregroundColor(Theme.text)
        .padding(.horizontal, 16)
        .task(id: query) {
            let q = trimmed
            guard !q.isEmpty else { suggestions = []; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let result = await Suggest.fetch(q)
            if !Task.isCancelled { suggestions = result }
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.self) { text in
                Button { submit(text) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: showingRecents ? "clock.arrow.circlepath" : "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundColor(Theme.text2)
                            .frame(width: 20)
                        Text(text)
                            .font(.system(size: 16))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.text2)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if showingRecents {
                Button {
                    RecentSearches.clear()
                    recents = []
                } label: {
                    Text("Suchverlauf löschen")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke))
    }

    private func submit(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        query = q
        recents = RecentSearches.add(q)
        focused = false
        onSearch(q)
    }
}

struct ModeSwitcher: View {
    @Binding var mode: AppMode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            segment(.video, "Videos", "play.fill")
            segment(.music, "Musik", "music.note")
        }
        .padding(4)
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.stroke))
    }

    private func segment(_ m: AppMode, _ title: String, _ icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { mode = m }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if mode == m {
                    Capsule()
                        .fill(Theme.accentGradient)
                        .glow(radius: 12, opacity: 0.6)
                        .matchedGeometryEffect(id: "segment", in: ns)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Hinweise

struct InfoCard: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundColor(Theme.accent)
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            Text(message).font(.system(size: 14)).foregroundColor(Theme.text2)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.accentGradient)
                        .clipShape(Capsule())
                        .glow(radius: 10, opacity: 0.5)
                }
                .padding(.top, 4)
            }
        }
        .foregroundColor(Theme.text)
        .card()
        .padding(.horizontal, 16)
    }
}

struct LoadingView: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView().tint(Theme.accent).scaleEffect(1.4)
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

// MARK: Bilder laden (mit Zwischenspeicher und Wiederholung)

enum ImageStore {
    static let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 400
        return c
    }()
}

@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var url: URL?
    private var task: Task<Void, Never>?

    func load(_ newURL: URL?) {
        if newURL == url && (image != nil || task != nil) { return }
        url = newURL
        task?.cancel()
        task = nil
        guard let target = newURL else { image = nil; return }
        if let cached = ImageStore.cache.object(forKey: target as NSURL) {
            image = cached
            return
        }
        image = nil
        task = Task { [weak self] in
            for attempt in 0..<3 {
                if Task.isCancelled { return }
                if let (data, _) = try? await URLSession.shared.data(from: target),
                   let img = UIImage(data: data) {
                    ImageStore.cache.setObject(img, forKey: target as NSURL)
                    guard !Task.isCancelled, let self, self.url == target else { return }
                    self.image = img
                    self.task = nil
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 700_000_000)
            }
            guard let self, self.url == target else { return }
            self.task = nil
        }
    }
}

struct RemoteImage: View {
    let url: URL?
    @StateObject private var loader = ImageLoader()

    var body: some View {
        ZStack {
            Theme.surfaceHi
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note").foregroundColor(Theme.text2)
            }
        }
        .animation(.easeOut(duration: 0.2), value: loader.image != nil)
        .onAppear { loader.load(url) }
        .onChange(of: url) { loader.load($0) }
    }
}
