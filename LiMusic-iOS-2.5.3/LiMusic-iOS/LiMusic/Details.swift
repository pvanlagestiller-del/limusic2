import SwiftUI

// MARK: Eigene YouTube-Playlists (für „Zur Playlist“)

@MainActor
final class YouTubePlaylists: ObservableObject {
    static let shared = YouTubePlaylists()
    @Published private(set) var playlists: [MediaItem] = []
    private var loaded = false

    func load(force: Bool) async {
        if loaded && !force { return }
        loaded = true
        playlists = (try? await Feeds.myPlaylists()) ?? []
    }
}

// MARK: Angaben zum Video im großen Player

struct DetailsSection: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var session: SessionState
    @State private var expanded = false
    @State private var showComments = false
    @State private var showChapters = false

    private static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        if let d = player.details {
            VStack(alignment: .leading, spacing: 12) {
                let info = [d.views, d.date].filter { !$0.isEmpty }.joined(separator: " • ")
                if !info.isEmpty {
                    Text(info)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.text2)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { needLogin { await player.setLikeStatus(.like) } } label: {
                            chipLabel(d.likes.isEmpty ? "Mag ich" : d.likes,
                                      d.likeStatus == .like ? "hand.thumbsup.fill" : "hand.thumbsup",
                                      active: d.likeStatus == .like)
                        }
                        Button { needLogin { await player.setLikeStatus(.dislike) } } label: {
                            chipLabel("", d.likeStatus == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                                      active: d.likeStatus == .dislike)
                        }
                        Button {
                            needLogin { await player.addToYouTubePlaylist("WL", name: "Später ansehen") }
                        } label: {
                            chipLabel("Später", "clock", active: false)
                        }
                        Menu {
                            ForEach(Self.speeds, id: \.self) { s in
                                Button {
                                    player.setSpeed(s)
                                } label: {
                                    if player.speed == s {
                                        Label(Self.speedTitle(s), systemImage: "checkmark")
                                    } else {
                                        Text(Self.speedTitle(s))
                                    }
                                }
                            }
                        } label: {
                            chipLabel(Self.speedTitle(player.speed), "speedometer", active: player.speed != 1)
                        }
                        if player.videoMode {
                            Menu {
                                if player.qualities.isEmpty {
                                    Text("Qualität legt YouTube hier selbst fest")
                                } else {
                                    ForEach(player.qualities, id: \.self) { q in
                                        Button {
                                            player.setQuality(q)
                                        } label: {
                                            if player.quality == q {
                                                Label(Self.qualityTitle(q), systemImage: "checkmark")
                                            } else {
                                                Text(Self.qualityTitle(q))
                                            }
                                        }
                                    }
                                }
                            } label: {
                                chipLabel(player.quality.isEmpty ? "Qualität" : Self.qualityTitle(player.quality),
                                          "tv", active: false)
                            }
                        }
                        if !d.chapters.isEmpty {
                            Button { showChapters = true } label: {
                                chipLabel("Kapitel", "list.bullet", active: false)
                            }
                        }
                        if d.commentsToken != nil {
                            Button { showComments = true } label: {
                                chipLabel("Kommentare", "text.bubble", active: false)
                            }
                        }
                    }
                }

                if !d.description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(d.description)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.text.opacity(0.9))
                            .lineLimit(expanded ? nil : 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                        } label: {
                            Text(expanded ? "Weniger anzeigen" : "Mehr anzeigen")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .padding(14)
                    .background(Theme.surface.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
                }
            }
            .sheet(isPresented: $showComments) {
                if let token = d.commentsToken {
                    CommentsSheet(token: token)
                }
            }
            .sheet(isPresented: $showChapters) {
                ChaptersSheet(chapters: d.chapters).environmentObject(player)
            }
        }
    }

    private func needLogin(_ work: @escaping () async -> Void) {
        if session.isLoggedIn {
            Task { await work() }
        } else {
            session.showLogin = true
        }
    }

    private func chipLabel(_ title: String, _ icon: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            if !title.isEmpty { Text(title) }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(active ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(active ? Theme.accent : Theme.stroke))
    }

    static func speedTitle(_ s: Double) -> String {
        if s == 1 { return "Normal" }
        let text = String(format: "%.2f", s)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: ",")
        return text + "×"
    }

    static func qualityTitle(_ q: String) -> String {
        switch q {
        case "highres": return "Maximal"
        case "hd2160": return "2160p (4K)"
        case "hd1440": return "1440p"
        case "hd1080": return "1080p"
        case "hd720": return "720p"
        case "large": return "480p"
        case "medium": return "360p"
        case "small": return "240p"
        case "tiny": return "144p"
        case "auto": return "Automatisch"
        default: return q
        }
    }
}

// MARK: Kapitel

struct ChaptersSheet: View {
    let chapters: [Chapter]
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(chapters) { c in
                Button {
                    player.seek(to: c.start)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(c.time)
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(Theme.accent)
                            .frame(width: 58, alignment: .leading)
                        Text(c.title)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.text)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Kapitel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

// MARK: Kommentare

struct CommentsSheet: View {
    let token: String
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [Comment] = []
    @State private var nextToken: String?
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(comments) { c in
                        row(c)
                    }
                    if loading {
                        LoadingView()
                    } else if failed && comments.isEmpty {
                        Text("Kommentare konnten nicht geladen werden.")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.text2)
                    } else if comments.isEmpty {
                        Text("Keine Kommentare.")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.text2)
                    } else if nextToken != nil {
                        Color.clear
                            .frame(height: 1)
                            .task(id: comments.count) { await load() }
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Kommentare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task {
                nextToken = token
                await load()
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func load() async {
        guard !loading, let t = nextToken else { return }
        loading = true
        do {
            let page = try await InnerTube.shared.comments(token: t)
            let known = Set(comments.map { $0.id })
            let fresh = page.comments.filter { !known.contains($0.id) }
            comments += fresh
            nextToken = (fresh.isEmpty || page.next == t) ? nil : page.next
        } catch {
            failed = true
            nextToken = nil
        }
        loading = false
    }

    private func row(_ c: Comment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: c.avatar)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(c.author)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text(c.time)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text2)
                        .lineLimit(1)
                }
                Text(c.text)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                HStack(spacing: 14) {
                    if !c.likes.isEmpty {
                        Label(c.likes, systemImage: "hand.thumbsup")
                    }
                    if !c.replies.isEmpty && c.replies != "0" {
                        Label(c.replies, systemImage: "bubble.left")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.text2)
            }
        }
    }
}

// MARK: Abonnieren auf der Kanalseite

struct ChannelSubscribeButton: View {
    let channelId: String
    let name: String
    @EnvironmentObject private var session: SessionState
    @State private var subscribed: Bool?
    @State private var busy = false

    var body: some View {
        Button {
            guard session.isLoggedIn else { session.showLogin = true; return }
            guard !busy else { return }
            busy = true
            let target = !(subscribed ?? false)
            Task {
                do {
                    try await InnerTube.shared.setSubscribed(channelId: channelId, target)
                    subscribed = target
                    Feeds.clearCache()
                    PlayerController.shared.showNotice(target ? "\(name) abonniert" : "Abo von \(name) beendet")
                } catch {
                    PlayerController.shared.showNotice("Abonnieren hat nicht geklappt – bist du angemeldet?")
                }
                busy = false
            }
        } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().tint(.white).scaleEffect(0.7)
                } else {
                    Image(systemName: subscribed == true ? "checkmark" : "bell.badge.fill")
                }
                Text(subscribed == true ? "Abonniert" : "Abonnieren")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(subscribed == true ? AnyShapeStyle(Theme.surfaceHi) : AnyShapeStyle(Theme.accentGradient))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(subscribed == true ? Theme.stroke : Theme.accent))
        }
        .task {
            subscribed = await InnerTube.shared.channelSubscribed(channelId)
        }
    }
}

// MARK: Gesten auf dem Video (Doppeltipp spulen, Shorts wischen)

struct VideoGestureLayer: View {
    @EnvironmentObject private var player: PlayerController
    @State private var flash: String?
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            half(-10)
            half(10)
        }
        .overlay {
            if let f = flash {
                Text(f)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40).onEnded { v in
                guard abs(v.translation.height) > abs(v.translation.width) else { return }
                if player.current?.isShort == true {
                    if v.translation.height < -50 {
                        player.next()
                    } else if v.translation.height > 50 {
                        player.skipBack()
                    }
                } else if v.translation.height > 90 {
                    player.isExpanded = false
                }
            }
        )
    }

    private func half(_ delta: Double) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                player.seek(to: max(0, player.time + delta))
                show(delta < 0 ? "−10 s" : "+10 s")
            }
            .onTapGesture {
                player.toggle()
            }
    }

    private func show(_ text: String) {
        flashTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { flash = text }
        flashTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { flash = nil }
        }
    }
}
