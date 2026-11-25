import SwiftUI

enum AppTab: Int, CaseIterable {
    case home, explore, player, library, profile

    var title: String {
        switch self {
        case .home: return "Start"
        case .explore: return "Entdecken"
        case .player: return "Player"
        case .library: return "Bibliothek"
        case .profile: return "Profil"
        }
    }

    func icon(selected: Bool) -> String {
        switch self {
        case .home: return selected ? "house.fill" : "house"
        case .explore: return selected ? "safari.fill" : "safari"
        case .player: return selected ? "play.circle.fill" : "play.circle"
        case .library: return selected ? "books.vertical.fill" : "books.vertical"
        case .profile: return selected ? "person.fill" : "person"
        }
    }
}

struct RootView: View {
    @StateObject private var player = PlayerController.shared
    @StateObject private var session = SessionState()
    @AppStorage("startMode") private var startMode = AppMode.video.rawValue

    @State private var mode: AppMode = .video
    @State private var tab: AppTab = .home
    @State private var path = NavigationPath()
    @State private var didSetMode = false
    @State private var newPlaylistName = ""

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                NavigationStack(path: $path) {
                    tabContent
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: Route.self) { route in
                            destination(route)
                        }
                }
                BottomBar(tab: tab, playerActive: player.current != nil, onSelect: select)
            }
            .background(Theme.background.ignoresSafeArea())

            PlayerOverlay()
        }
        .environmentObject(player)
        .environmentObject(session)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear {
            if !didSetMode {
                mode = AppMode(rawValue: startMode) ?? .video
                didSetMode = true
            }
        }
        .onChange(of: session.pendingSearch) { q in
            if let q {
                path.append(Route.search(q, mode))
                session.pendingSearch = nil
            }
        }
        .onChange(of: session.pendingRoute) { r in
            if let r {
                if tab == .profile || tab == .player { tab = .home }
                path.append(r)
                session.pendingRoute = nil
            }
        }
        .onChange(of: session.newPlaylistFor) { item in
            if item != nil { newPlaylistName = "" }
        }
        .alert("Neue Playlist", isPresented: Binding(
            get: { session.newPlaylistFor != nil },
            set: { if !$0 { session.newPlaylistFor = nil } }
        )) {
            TextField("Name", text: $newPlaylistName)
            Button("Anlegen") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let item = session.newPlaylistFor, !name.isEmpty {
                    let id = LocalLibrary.shared.createPlaylist(name)
                    LocalLibrary.shared.add(item, to: id)
                }
                session.newPlaylistFor = nil
            }
            Button("Abbrechen", role: .cancel) { session.newPlaylistFor = nil }
        }
        .task {
            if !FilterUpdater.baseURL.isEmpty { await FilterUpdater.update() }
        }
        .task {
            guard await InnerTube.shared.isLoggedIn() else { return }
            await YouTubePlaylists.shared.load(force: false)
            let fresh = await Feeds.newSubscriptionCount()
            if fresh > 0 {
                player.showNotice(fresh == 1 ? "1 neues Video von deinen Abos – unter „Entdecken“"
                                             : "\(fresh) neue Videos von deinen Abos – unter „Entdecken“")
            }
        }
        .sheet(item: $session.classic) { page in
            ClassicSheet(page: page)
        }
        .sheet(isPresented: $session.showLogin) {
            LoginSheet().environmentObject(session)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .home, .player:
            FeedScreen(mode: $mode, kind: .home, onSearch: search)
        case .explore:
            FeedScreen(mode: $mode, kind: .explore, onSearch: search)
        case .library:
            FeedScreen(mode: $mode, kind: .library, onSearch: search)
        case .profile:
            ProfileScreen()
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .local(let id):
            LocalPlaylistScreen(id: id)
        case .search(let q, let m):
            SearchScreen(query: q, mode: m)
        case .collection(let item):
            ListScreen(title: item.title, key: "collection-\(item.id)", header: item) {
                try await Feeds.collection(item)
            }
        case .shelf(let shelf):
            ListScreen(title: shelf.title, key: "shelf-\(shelf.id)") {
                [Shelf(title: "", items: shelf.items, style: (shelf.style == .grid || shelf.style == .shorts) ? .grid : .list,
                       radio: shelf.radio)]
            }
        }
    }

    private func search(_ q: String) {
        path.append(Route.search(q, mode))
    }

    private func select(_ t: AppTab) {
        if t == .player {
            if player.current != nil {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { player.isExpanded = true }
            }
            return
        }
        if t != tab { tab = t }
        path = NavigationPath()
    }
}

struct BottomBar: View {
    let tab: AppTab
    let playerActive: Bool
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { t in
                Button { onSelect(t) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon(selected: isHighlighted(t)))
                            .font(.system(size: 21))
                        Text(t.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(isHighlighted(t) ? Theme.accent : Theme.text.opacity(0.85))
                    .opacity(t == .player && !playerActive ? 0.45 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 9)
        .frame(height: PlayerLayout.barHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.stroke))
                .padding(.bottom, -60)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func isHighlighted(_ t: AppTab) -> Bool {
        t == .player ? playerActive : t == tab
    }
}
