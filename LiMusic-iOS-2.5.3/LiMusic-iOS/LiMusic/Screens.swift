import SwiftUI

@MainActor
final class FeedModel: ObservableObject {
    @Published var shelves: [Shelf] = []
    @Published var loading = false
    @Published var error: String?
    private var key = ""

    func load(key: String, force: Bool, _ loader: @escaping () async throws -> [Shelf]) async {
        if !force && key == self.key && !shelves.isEmpty { return }
        if key != self.key { shelves = [] }
        self.key = key
        loading = true
        error = nil
        do {
            let result = try await loader()
            if self.key == key { shelves = result }
        } catch {
            if self.key == key {
                self.error = error.localizedDescription
                shelves = []
            }
        }
        loading = false
    }

    var allItems: [MediaItem] { shelves.flatMap { $0.items } }

    @Published var canLoadMore = false
    @Published var page = 0
    private var loadingMore = false
    private var emptyStreak = 0

    func loadMore(_ more: @escaping () async throws -> [Shelf], hasMore: @escaping () -> Bool) async {
        guard canLoadMore, !loadingMore else { return }
        loadingMore = true
        let k = key
        let extra = (try? await more()) ?? []
        if key == k {
            shelves += extra
            emptyStreak = extra.isEmpty ? emptyStreak + 1 : 0
            canLoadMore = hasMore() && emptyStreak < 3
        }
        loadingMore = false
        page += 1
    }
}

// MARK: Start / Entdecken / Bibliothek

struct FeedScreen: View {
    @Binding var mode: AppMode
    let kind: FeedKind
    let onSearch: (String) -> Void

    @StateObject private var model = FeedModel()
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var session: SessionState

    private var taskKey: String { "\(kind.rawValue)-\(mode.rawValue)-\(session.generation)" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                TopArea(mode: $mode, onSearch: onSearch)
                    .padding(.top, 6)

                if kind != .home {
                    Text(kind == .explore ? "Entdecken" : "Bibliothek")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 16)
                        .padding(.bottom, -10)
                }

                if kind == .library {
                    LocalLibrarySection()
                }

                if !session.isLoggedIn && kind != .explore {
                    InfoCard(icon: "person.crop.circle.badge.plus",
                             title: "Mit YouTube verbinden",
                             message: "Melde dich an, um deine Empfehlungen, Abos, Playlists und den Verlauf zu sehen.",
                             actionTitle: "Anmelden") { session.showLogin = true }
                }

                if model.loading && model.shelves.isEmpty {
                    LoadingView()
                }

                if let e = model.error {
                    InfoCard(icon: "exclamationmark.triangle.fill", title: "Laden fehlgeschlagen",
                             message: e, actionTitle: "Erneut versuchen") {
                        Task { await reload(force: true) }
                    }
                }

                if !model.loading && model.error == nil && model.shelves.isEmpty {
                    InfoCard(icon: "sparkles", title: "Noch nichts da",
                             message: "Hier ist gerade nichts zu sehen. Suche oben nach etwas oder ziehe zum Aktualisieren nach unten.")
                }

                ForEach(model.shelves) { shelf in
                    ShelfView(shelf: shelf)
                }

                if model.canLoadMore {
                    LoadingView()
                        .task(id: model.page) {
                            let k = kind
                            let m = mode
                            await model.loadMore({ try await Feeds.more(k, mode: m) },
                                                 hasMore: { Feeds.hasMore(k, mode: m) })
                        }
                }
            }
            .padding(.bottom, player.current == nil ? 24 : 96)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .refreshable { await reload(force: true) }
        .task(id: taskKey) { await reload(force: false) }
    }

    private func reload(force: Bool) async {
        let k = kind
        let m = mode
        await model.load(key: taskKey, force: force) {
            try await Feeds.load(k, mode: m, force: force)
        }
        model.canLoadMore = k == .home && Feeds.hasMore(k, mode: m)
    }
}

// MARK: Suche / Sammlung / „Alle“

struct ListScreen: View {
    let title: String
    let key: String
    var header: MediaItem?
    let loader: () async throws -> [Shelf]

    @StateObject private var model = FeedModel()
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let h = header { headerView(h) }
                if model.loading && model.shelves.isEmpty { LoadingView() }
                if let e = model.error {
                    InfoCard(icon: "exclamationmark.triangle.fill", title: "Laden fehlgeschlagen",
                             message: e, actionTitle: "Erneut versuchen") {
                        Task { await model.load(key: key, force: true, loader) }
                    }
                }
                if !model.loading && model.error == nil && model.allItems.isEmpty {
                    InfoCard(icon: "magnifyingglass", title: "Keine Ergebnisse", message: "Versuche einen anderen Suchbegriff.")
                }
                ForEach(model.shelves) { shelf in
                    ShelfView(shelf: shelf)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, player.current == nil ? 24 : 96)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(key: key, force: false, loader) }
    }

    private func headerView(_ h: MediaItem) -> some View {
        VStack(spacing: 14) {
            Thumb(url: h.thumbnail, ratio: (h.isMusic || h.isChannel) ? 1 : 16 / 9, corner: h.isChannel ? 999 : 20)
                .frame(maxWidth: h.isChannel ? CGFloat(150) : (h.isMusic ? CGFloat(230) : CGFloat.infinity))
                .glow(radius: 26, opacity: 0.35)
            Text(h.title)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
            if !h.subtitle.isEmpty {
                Text(h.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text2)
                    .multilineTextAlignment(.center)
            }
            if h.isChannel, let cid = h.browseId {
                ChannelSubscribeButton(channelId: cid, name: h.title)
            }
            HStack(spacing: 12) {
                Button { playAll(shuffle: false) } label: {
                    Label("Abspielen", systemImage: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Theme.accentGradient)
                        .clipShape(Capsule())
                        .glow(radius: 12, opacity: 0.5)
                }
                Button { playAll(shuffle: true) } label: {
                    Label("Zufall", systemImage: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Theme.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.stroke))
                }
            }
            .disabled(model.allItems.isEmpty)
        }
        .foregroundColor(Theme.text)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func playAll(shuffle: Bool) {
        var items = model.allItems.filter { $0.videoId != nil }
        if shuffle { items.shuffle() }
        guard let first = items.first else { return }
        player.play(first, in: items)
    }
}

// MARK: Profil

struct ProfileScreen: View {
    @EnvironmentObject private var session: SessionState
    @EnvironmentObject private var player: PlayerController
    @AppStorage("adblock") private var adblock = true
    @AppStorage("autoPiP") private var autoPiP = true
    @AppStorage("startMode") private var startMode = AppMode.video.rawValue
    @AppStorage("filterURL") private var filterURL = ""
    @AppStorage("autoFullscreen") private var autoFullscreen = true
    @AppStorage("autoplay") private var autoplay = true
    @State private var filterStatus: String?
    @State private var filterBusy = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image("Logo").resizable().scaledToFit().frame(width: 84, height: 84)
                        .glow(radius: 18, opacity: 0.6)
                    Text("LiMusic").font(.system(size: 28, weight: .bold))
                    Text("Version \(version)").font(.system(size: 13)).foregroundColor(Theme.text2)
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Konto").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text2)
                    if session.isLoggedIn {
                        Label("Mit YouTube verbunden", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Button(role: .destructive) {
                            Task { await session.logout() }
                        } label: {
                            Text("Abmelden").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent)
                        }
                    } else {
                        Text("Nicht angemeldet").foregroundColor(Theme.text2)
                        Button { session.showLogin = true } label: {
                            Label("Mit Google anmelden", systemImage: "person.crop.circle.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(Theme.accentGradient)
                                .clipShape(Capsule())
                                .glow(radius: 12, opacity: 0.5)
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Einstellungen").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text2)
                    Toggle(isOn: $adblock) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Werbeblocker")
                            Text("Änderung wirkt nach Neustart der App").font(.system(size: 12)).foregroundColor(Theme.text2)
                        }
                    }
                    Toggle(isOn: $autoplay) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Autoplay")
                            Text("Nach dem Ende automatisch den nächsten Titel spielen").font(.system(size: 12)).foregroundColor(Theme.text2)
                        }
                    }
                    Toggle(isOn: $autoFullscreen) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Querformat = Vollbild")
                            Text("iPhone drehen startet das Video im Vollbild").font(.system(size: 12)).foregroundColor(Theme.text2)
                        }
                    }
                    Toggle(isOn: $autoPiP) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Schwebendes Video beim Verlassen")
                            Text("Video läuft als Bild-in-Bild weiter").font(.system(size: 12)).foregroundColor(Theme.text2)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Beim Start öffnen")
                        Picker("Beim Start öffnen", selection: $startMode) {
                            Text("Videos").tag(AppMode.video.rawValue)
                            Text("Musik").tag(AppMode.music.rawValue)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .tint(Theme.accent)
                .foregroundColor(Theme.text)
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Werbefilter-Updates").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text2)
                    Text("Adresse eines öffentlichen Ordners mit antiad.js und antiad-filter.json. Die App prüft bei jedem Start auf neue Filter.")
                        .font(.system(size: 13)).foregroundColor(Theme.text2)
                    TextField("", text: $filterURL,
                              prompt: Text("https://raw.githubusercontent.com/…/main").foregroundColor(Theme.text2))
                        .font(.system(size: 14))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(Theme.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    HStack(spacing: 10) {
                        Button {
                            filterBusy = true
                            Task {
                                filterStatus = await FilterUpdater.update()
                                filterBusy = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if filterBusy { ProgressView().tint(.white) }
                                Text("Jetzt prüfen")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(Theme.accentGradient)
                            .clipShape(Capsule())
                        }
                        .disabled(filterBusy || filterURL.isEmpty)
                        Button {
                            FilterUpdater.reset()
                            filterStatus = "Zurück auf eingebaute Filter – wirkt nach Neustart."
                        } label: {
                            Text("Zurücksetzen")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.text)
                                .frame(maxWidth: .infinity).frame(height: 42)
                                .background(Theme.surfaceHi)
                                .clipShape(Capsule())
                        }
                    }
                    if let filterStatus {
                        Text(filterStatus).font(.system(size: 13)).foregroundColor(Theme.text2)
                    } else if let d = FilterUpdater.lastUpdate {
                        Text("Zuletzt geladen: \(d.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 13)).foregroundColor(Theme.text2)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Klassische Ansicht").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text2)
                    Text("Falls YouTube etwas umgebaut hat und Inhalte fehlen, geht es hier direkt zur Webseite – mit Werbeblocker.")
                        .font(.system(size: 13)).foregroundColor(Theme.text2)
                    classicButton("YouTube öffnen", "play.rectangle.fill", "https://m.youtube.com/")
                    classicButton("YouTube Music öffnen", "music.note", "https://music.youtube.com/")
                }
                .card()

                Text("LiMusic ist eine private App für LiMaD OS.\nNicht mit YouTube oder Google verbunden.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .foregroundColor(Theme.text)
            .padding(.horizontal, 16)
            .padding(.bottom, player.current == nil ? 24 : 96)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private func classicButton(_ title: String, _ icon: String, _ url: String) -> some View {
        Button {
            if let u = URL(string: url) { session.classic = ClassicPage(url: u) }
        } label: {
            HStack {
                Label(title, systemImage: icon).font(.system(size: 16, weight: .medium))
                Spacer()
                Image(systemName: "arrow.up.right").foregroundColor(Theme.text2)
            }
            .foregroundColor(Theme.text)
            .padding(.vertical, 6)
        }
    }
}

// MARK: Suche mit Filter-Reitern

struct SearchScreen: View {
    let query: String
    let mode: AppMode
    @State private var filter: MusicFilter = .all
    @State private var video: VideoFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if mode == .music {
                        ForEach(MusicFilter.allCases) { f in
                            chip(f.title, f.icon, active: filter == f) { filter = f }
                        }
                    } else {
                        ForEach(VideoFilter.allCases) { f in
                            chip(f.title, f.icon, active: video == f) { video = f }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Theme.background)

            ListScreen(title: "„\(query)“",
                       key: "search-\(mode.rawValue)-\(filter.rawValue)-\(video.rawValue)-\(query)") {
                try await Feeds.search(query, mode: mode, filter: filter, video: video)
            }
            .id("\(filter.rawValue)-\(video.rawValue)")
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private func chip(_ title: String, _ icon: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { action() }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(active ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Theme.accent : Theme.stroke))
                .shadow(color: Theme.accent.opacity(active ? 0.5 : 0), radius: 8)
        }
        .buttonStyle(.plain)
    }
}
