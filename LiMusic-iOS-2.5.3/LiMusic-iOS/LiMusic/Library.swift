import SwiftUI

// MARK: Eigene Playlists + „Gefällt mir“ (lokal gespeichert)

@MainActor
final class LocalLibrary: ObservableObject {
    static let shared = LocalLibrary()

    @Published private(set) var playlists: [LocalPlaylist] = []
    @Published private(set) var liked: [SavedTrack] = []

    private struct Store: Codable {
        var playlists: [LocalPlaylist]
        var liked: [SavedTrack]
    }

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: fileURL),
           let store = try? JSONDecoder().decode(Store.self, from: data) {
            playlists = store.playlists
            liked = store.liked
        }
    }

    private func save() {
        let store = Store(playlists: playlists, liked: liked)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // „Gefällt mir“

    func isLiked(_ item: MediaItem?) -> Bool {
        guard let v = item?.videoId else { return false }
        return liked.contains { $0.videoId == v }
    }

    func toggleLike(_ item: MediaItem) {
        guard let v = item.videoId else { return }
        let nowLiked: Bool
        if let i = liked.firstIndex(where: { $0.videoId == v }) {
            liked.remove(at: i)
            nowLiked = false
        } else {
            liked.insert(SavedTrack(item), at: 0)
            nowLiked = true
        }
        save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let music = item.isMusic
        PlayerController.shared.noteLike(videoId: v, liked: nowLiked)
        Task { await InnerTube.shared.setLike(videoId: v, liked: nowLiked, music: music) }
    }

    /// Nur die lokale Liste anpassen (YouTube ist schon informiert)
    func setLocal(_ item: MediaItem, liked on: Bool) {
        guard let v = item.videoId else { return }
        let has = liked.contains { $0.videoId == v }
        if on && !has {
            liked.insert(SavedTrack(item), at: 0)
            save()
        } else if !on && has {
            liked.removeAll { $0.videoId == v }
            save()
        }
    }

    // Playlists

    @discardableResult
    func createPlaylist(_ name: String) -> UUID {
        let p = LocalPlaylist(id: UUID(), name: name, tracks: [])
        playlists.append(p)
        save()
        return p.id
    }

    func add(_ item: MediaItem, to id: UUID) {
        guard item.videoId != nil, let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        let t = SavedTrack(item)
        guard !playlists[i].tracks.contains(where: { $0.videoId == t.videoId }) else { return }
        playlists[i].tracks.append(t)
        save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = name
        save()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func tracks(_ id: UUID?) -> [SavedTrack] {
        guard let id else { return liked }
        return playlists.first { $0.id == id }?.tracks ?? []
    }

    func name(_ id: UUID?) -> String {
        guard let id else { return "Gefällt mir" }
        return playlists.first { $0.id == id }?.name ?? "Playlist"
    }

    func remove(at offsets: IndexSet, from id: UUID?) {
        if let id {
            guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
            playlists[i].tracks.remove(atOffsets: offsets)
        } else {
            liked.remove(atOffsets: offsets)
        }
        save()
    }

    func move(from: IndexSet, to: Int, in id: UUID?) {
        if let id {
            guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
            playlists[i].tracks.move(fromOffsets: from, toOffset: to)
        } else {
            liked.move(fromOffsets: from, toOffset: to)
        }
        save()
    }
}

// MARK: „Zur Playlist“-Menü

struct PlaylistMenu<L: View>: View {
    let item: MediaItem
    let label: () -> L
    @ObservedObject private var lib = LocalLibrary.shared
    @ObservedObject private var yt = YouTubePlaylists.shared
    @EnvironmentObject private var session: SessionState

    init(item: MediaItem, @ViewBuilder label: @escaping () -> L) {
        self.item = item
        self.label = label
    }

    var body: some View {
        Menu {
            ForEach(lib.playlists) { p in
                Button(p.name) { lib.add(item, to: p.id) }
            }
            Button {
                session.newPlaylistFor = item
            } label: {
                Label("Neue Playlist …", systemImage: "plus")
            }
            if session.isLoggedIn {
                Section("YouTube-Konto") {
                    Button {
                        Task { await PlayerController.shared.addToYouTubePlaylist("WL", name: "Später ansehen", item: item) }
                    } label: {
                        Label("Später ansehen", systemImage: "clock")
                    }
                    ForEach(yt.playlists) { p in
                        Button(p.title) {
                            let pid = String((p.browseId ?? "").dropFirst(2))
                            Task { await PlayerController.shared.addToYouTubePlaylist(pid, name: p.title, item: item) }
                        }
                    }
                }
            }
        } label: {
            label()
        }
    }
}

// MARK: Bereich „Meine Playlists“ in der Bibliothek

struct LocalLibrarySection: View {
    @ObservedObject private var lib = LocalLibrary.shared
    @State private var askName = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Meine Playlists")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                Button {
                    newName = ""
                    askName = true
                } label: {
                    Label("Neu", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    NavigationLink(value: Route.local(nil)) {
                        LocalTile(title: "Gefällt mir", count: lib.liked.count, icon: "heart.fill",
                                  thumb: lib.liked.first?.thumbnail)
                    }
                    .buttonStyle(PressStyle())
                    ForEach(lib.playlists) { p in
                        NavigationLink(value: Route.local(p.id)) {
                            LocalTile(title: p.name, count: p.tracks.count, icon: "music.note.list",
                                      thumb: p.tracks.first?.thumbnail)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .alert("Neue Playlist", isPresented: $askName) {
            TextField("Name", text: $newName)
            Button("Anlegen") {
                let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { lib.createPlaylist(n) }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

struct LocalTile: View {
    let title: String
    let count: Int
    let icon: String
    let thumb: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let t = thumb, let url = URL(string: t) {
                    RemoteImage(url: url)
                    Color.black.opacity(0.35)
                } else {
                    Theme.accentGradient
                }
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6)
            }
            .frame(width: 156, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
            Text("\(count) Titel")
                .font(.system(size: 12))
                .foregroundColor(Theme.text2)
        }
        .frame(width: 156, alignment: .leading)
    }
}

// MARK: Eigene Playlist anzeigen und bearbeiten

struct LocalPlaylistScreen: View {
    let id: UUID?
    @ObservedObject private var lib = LocalLibrary.shared
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let tracks = lib.tracks(id).map { $0.item }
        List {
            HStack(spacing: 12) {
                Button { playAll(tracks, shuffle: false) } label: {
                    Label("Abspielen", systemImage: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Theme.accentGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button { playAll(tracks, shuffle: true) } label: {
                    Label("Zufall", systemImage: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Theme.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.stroke))
                }
                .buttonStyle(.plain)
            }
            .disabled(tracks.isEmpty)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if tracks.isEmpty {
                Text(id == nil
                     ? "Tippe im Player auf das Herz, um Titel hier zu sammeln."
                     : "Lange auf eine Kachel drücken → „Zur Playlist“, oder im Player auf das Plus.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text2)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(Array(tracks.enumerated()), id: \.offset) { pair in
                Button { player.play(pair.element, in: tracks) } label: {
                    ListRow(item: pair.element, isCurrent: player.current?.videoId == pair.element.videoId)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.stroke)
            }
            .onDelete { lib.remove(at: $0, from: id) }
            .onMove { lib.move(from: $0, to: $1, in: id) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: player.current == nil ? 0 : 80)
        }
        .navigationTitle(lib.name(id))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let id {
                    Menu {
                        Button {
                            newName = lib.name(id)
                            renaming = true
                        } label: {
                            Label("Umbenennen", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            lib.deletePlaylist(id)
                            dismiss()
                        } label: {
                            Label("Playlist löschen", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                if !tracks.isEmpty { EditButton() }
            }
        }
        .alert("Umbenennen", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Speichern") {
                let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id, !n.isEmpty { lib.rename(id, to: n) }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func playAll(_ tracks: [MediaItem], shuffle: Bool) {
        var list = tracks
        if shuffle { list.shuffle() }
        guard let first = list.first else { return }
        player.play(first, in: list)
    }
}

// MARK: Warteschlange bearbeiten

struct QueueSheet: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let c = player.current {
                    Section {
                        ListRow(item: c, isCurrent: true)
                            .listRowBackground(Theme.surface)
                    } header: {
                        Text("Läuft gerade")
                    }
                }
                Section {
                    ForEach(player.upcoming) { entry in
                        Button { player.playAt(entry.index) } label: {
                            ListRow(item: entry.item)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.surface)
                    }
                    .onDelete { player.removeUpcoming(at: $0) }
                    .onMove { player.moveUpcoming(from: $0, to: $1) }
                } header: {
                    Text("Als Nächstes")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Warteschlange")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}
