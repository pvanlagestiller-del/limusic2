import SwiftUI

/// Feste Positionen für Mini- und Vollbild-Player (in Bildschirmkoordinaten).
struct PlayerLayout {
    let size: CGSize
    let safe: UIEdgeInsets

    static let barHeight: CGFloat = 62
    static let miniHeight: CGFloat = 64

    var miniRect: CGRect {
        CGRect(x: 12, y: size.height - safe.bottom - Self.barHeight - Self.miniHeight - 8,
               width: size.width - 24, height: Self.miniHeight)
    }

    func miniMediaRect(music: Bool) -> CGRect {
        CGRect(x: miniRect.minX + 8, y: miniRect.minY + 8, width: music ? 48 : 85, height: 48)
    }

    var fullTop: CGFloat { safe.top + 60 }

    func fullMediaRect(music: Bool, short: Bool) -> CGRect {
        guard short && !music else { return fullMediaRect(music: music) }
        let h = min(size.height * 0.55, (size.width - 24) * 16 / 9)
        let w = h * 9 / 16
        return CGRect(x: (size.width - w) / 2, y: fullTop, width: w, height: h)
    }

    func fullMediaRect(music: Bool) -> CGRect {
        if music {
            let s = min(size.width - 64, 340)
            return CGRect(x: (size.width - s) / 2, y: fullTop + 10, width: s, height: s)
        }
        let w = size.width - 24
        return CGRect(x: 12, y: fullTop, width: w, height: w * 9 / 16)
    }
}

/// Liegt über der ganzen App: Mini-Player, Vollbild-Player und der eine YouTube-WebView.
struct PlayerOverlay: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        GeometryReader { geo in
            let layout = PlayerLayout(size: geo.size, safe: SafeArea.insets)
            let music = !player.videoMode
            let rect = mediaRect(layout, music: music)

            ZStack(alignment: .topLeading) {
                if player.current != nil {
                    if player.isExpanded {
                        FullPlayerView(layout: layout)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .transition(.move(edge: .bottom))
                    } else {
                        MiniPlayerView(layout: layout)
                            .frame(width: layout.miniRect.width, height: layout.miniRect.height)
                            .position(x: layout.miniRect.midX, y: layout.miniRect.midY)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                PlayerWebView()
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: player.isExpanded ? 16 : 8, style: .continuous))
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(player.current == nil ? 0.011 : 1)
                    .allowsHitTesting(player.current != nil && player.isExpanded && !music)

                if music, let item = player.current {
                    Thumb(url: item.thumbnail, ratio: 1, corner: player.isExpanded ? 22 : 8)
                        .frame(width: rect.width, height: rect.height)
                        .glow(radius: player.isExpanded ? 30 : 0, opacity: 0.45)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                if player.isExpanded && !music && player.current != nil {
                    VideoGestureLayer()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                if player.isExpanded && !music && player.current != nil {
                    Button { player.enterFullscreen() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.25)))
                    }
                    .position(x: rect.maxX - 26, y: rect.minY + 26)
                }

                if player.isExpanded && player.isAd && !music {
                    Text("Werbung wird übersprungen …")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                        .position(x: rect.midX, y: rect.maxY - 18)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if let n = player.notice {
                    Text(n)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.accentGradient)
                        .clipShape(Capsule())
                        .shadow(color: Theme.accent.opacity(0.5), radius: 12)
                        .padding(.top, layout.safe.top + 8)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: player.isExpanded)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: player.current?.id)
        }
        .ignoresSafeArea()
    }

    private func mediaRect(_ l: PlayerLayout, music: Bool) -> CGRect {
        guard player.current != nil else { return CGRect(x: -40, y: -40, width: 8, height: 8) }
        return player.isExpanded ? l.fullMediaRect(music: music, short: player.current?.isShort == true) : l.miniMediaRect(music: music)
    }
}

// MARK: Mini-Player

struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlayerController
    @ObservedObject private var clock = PlayerController.shared.clock
    let layout: PlayerLayout

    var body: some View {
        let music = !player.videoMode
        HStack(spacing: 12) {
            Color.clear.frame(width: music ? 48 : 85, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text(player.current?.subtitle ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .frame(width: 40, height: 44)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .frame(width: 36, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(alignment: .bottom) {
            ProgressLine(value: player.duration > 0 ? player.time / player.duration : 0)
                .frame(height: 2)
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.accent.opacity(0.55), lineWidth: 1))
        .shadow(color: Theme.accent.opacity(0.35), radius: 14)
        .contentShape(Rectangle())
        .onTapGesture { player.isExpanded = true }
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { v in
                if v.translation.width < -60 { player.next() }
                else if v.translation.height < -30 { player.isExpanded = true }
                else if v.translation.height > 40 { player.stop() }
            }
        )
    }
}

// MARK: Vollbild-Player

struct FullPlayerView: View {
    @EnvironmentObject private var player: PlayerController
    @ObservedObject private var clock = PlayerController.shared.clock
    @EnvironmentObject private var session: SessionState
    let layout: PlayerLayout

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showLyrics = false
    @State private var showQueue = false
    @ObservedObject private var lib = LocalLibrary.shared
    @State private var lyrics: String?
    @State private var lyricsLoading = false

    var body: some View {
        let music = !player.videoMode
        let media = layout.fullMediaRect(music: music, short: player.current?.isShort == true)

        ZStack(alignment: .top) {
            background

            VStack(spacing: 0) {
                topBar
                    .padding(.top, layout.safe.top + 8)
                    .frame(width: layout.size.width)

                Color.clear.frame(height: media.maxY - (layout.safe.top + 52) + 22)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        titleRow(music: music)
                        scrubber
                        controls
                        secondary(music: music)
                        if player.current?.isMusic == true && showLyrics { lyricsView }
                        DetailsSection()
                        upNext
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, layout.safe.bottom + 24)
                    .frame(width: layout.size.width, alignment: .leading)
                }
                .frame(width: layout.size.width)
                .clipped()
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        }
        .foregroundColor(Theme.text)
        .task(id: "\(player.current?.id ?? "")-\(showLyrics)") {
            guard showLyrics, let c = player.current, c.isMusic, let vid = c.videoId else { return }
            lyrics = nil
            lyricsLoading = true
            let text = await Feeds.lyrics(videoId: vid)
            if !Task.isCancelled {
                lyrics = text
                lyricsLoading = false
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueSheet().environmentObject(player)
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.height > 90 && abs(v.translation.width) < 80 { player.isExpanded = false }
            }
        )
    }

    private var background: some View {
        ZStack {
            Theme.background
            LinearGradient(colors: [player.coverColor.opacity(0.95), player.coverColor.opacity(0.45), Theme.background],
                           startPoint: .top, endPoint: .bottom)
            Color.clear
                .overlay(RemoteImage(url: player.current?.thumbnail).blur(radius: 60).opacity(0.25))
                .clipped()
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .clipped()
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button { player.isExpanded = false } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 1) {
                Text("WIRD ABGESPIELT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(Theme.text2)
                Text(player.current?.isMusic == true ? "Musik" : "Video")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            AirPlayButton().frame(width: 34, height: 34).frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private func titleRow(music: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.current?.title ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
                Button {
                    if let r = player.current?.artistRoute ?? player.channelRoute {
                        player.isExpanded = false
                        session.pendingRoute = r
                    }
                } label: {
                    Text(player.current?.subtitle ?? "")
                        .font(.system(size: 15))
                        .foregroundColor((player.current?.artistRoute ?? player.channelRoute) != nil ? Theme.text : Theme.text2)
                        .lineLimit(1)
                }
                .disabled((player.current?.artistRoute ?? player.channelRoute) == nil)
                if let ch = player.channel {
                    Button {
                        if session.isLoggedIn {
                            Task { await player.toggleSubscribe() }
                        } else {
                            session.showLogin = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if player.subscribeBusy {
                                ProgressView().tint(.white).scaleEffect(0.7)
                            } else {
                                Image(systemName: ch.subscribed ? "checkmark" : "bell.badge.fill")
                            }
                            Text(ch.subscribed ? "Abonniert" : "Abonnieren")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(ch.subscribed ? AnyShapeStyle(Theme.surfaceHi) : AnyShapeStyle(Theme.accentGradient))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(ch.subscribed ? Theme.stroke : Theme.accent))
                    }
                    .padding(.top, 4)
                }
            }
            Spacer()
            if let c = player.current {
                Button { lib.toggleLike(c) } label: {
                    circleIcon(lib.isLiked(c) ? "heart.fill" : "heart", active: lib.isLiked(c))
                }
                PlaylistMenu(item: c) {
                    circleIcon("text.badge.plus", active: false)
                }
            }
        }
    }

    private func circleIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .semibold))
            .foregroundColor(active ? Theme.accent : Theme.text)
            .frame(width: 44, height: 44)
            .background(Theme.surface)
            .clipShape(Circle())
            .overlay(Circle().stroke(active ? Theme.accent : Theme.stroke))
    }

    private var scrubber: some View {
        let total = max(player.duration, 1)
        let shown = scrubbing ? scrubValue : player.time
        return VStack(spacing: 6) {
            Slider(value: Binding(get: { min(shown, total) }, set: { scrubValue = $0 }),
                   in: 0...total,
                   onEditingChanged: { editing in
                       if editing {
                           scrubValue = player.time
                           scrubbing = true
                       } else {
                           player.seek(to: scrubValue)
                           scrubbing = false
                       }
                   })
                .tint(Theme.accent)
            HStack {
                Text(Self.format(shown))
                Spacer()
                Text(player.duration > 0 ? Self.format(player.duration) : "--:--")
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundColor(Theme.text2)
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(player.shuffle ? Theme.accent : Theme.text2)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 28, weight: .semibold))
                    .frame(width: 56, height: 56)
            }
            Spacer()
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 78, height: 78)
                    .background(Theme.accentGradient)
                    .clipShape(Circle())
                    .glow(radius: 18, opacity: 0.7)
            }
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 28, weight: .semibold))
                    .frame(width: 56, height: 56)
            }
            Spacer()
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(player.repeatMode == .off ? Theme.text2 : Theme.accent)
                    .frame(width: 44, height: 44)
            }
        }
        .foregroundColor(Theme.text)
    }

    private func secondary(music: Bool) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if !music {
                    pill(player.isPiP ? "Zurückholen" : "Schwebend", player.isPiP ? "pip.exit" : "pip.enter",
                         active: player.isPiP) { player.togglePiP() }
                }
                pill("Klassisch", "safari", active: false) {
                    if let u = player.watchURL {
                        player.toggle()
                        session.classic = ClassicPage(url: u)
                    }
                }
                pill("Beenden", "xmark", active: false) { player.stop() }
            }
            HStack(spacing: 10) {
                if player.videoMode {
                    pill("UT", "captions.bubble", active: player.isCC) { player.toggleCC() }
                }
                if player.current?.isMusic == true {
                    pill(player.videoMode ? "Cover" : "Video", player.videoMode ? "photo" : "play.rectangle.fill",
                         active: player.videoMode) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { player.videoMode.toggle() }
                    }
                    pill("Text", "quote.bubble", active: showLyrics) {
                        withAnimation(.easeOut(duration: 0.2)) { showLyrics.toggle() }
                    }
                }
                Menu {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                        Button("\(m) Minuten") { player.setSleep(minutes: m) }
                    }
                    if player.sleepUntil != nil {
                        Button("Timer aus", role: .destructive) { player.setSleep(minutes: nil) }
                    }
                } label: {
                    pillLabel(sleepTitle, "moon.zzz", active: player.sleepUntil != nil)
                }
            }
        }
    }

    private var sleepTitle: String {
        guard let until = player.sleepUntil else { return "Timer" }
        let minutes = max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
        return "\(minutes) Min."
    }

    private func pillLabel(_ title: String, _ icon: String, active: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .foregroundColor(active ? .white : Theme.text)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(active ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(active ? Theme.accent : Theme.stroke))
    }

    private func pill(_ title: String, _ icon: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            pillLabel(title, icon, active: active)
        }
    }

    private var lyricsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Songtext")
                .font(.system(size: 20, weight: .bold))
            if lyricsLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.accent)
                    Text("Songtext wird geladen …").foregroundColor(Theme.text2)
                }
                .font(.system(size: 14))
            } else if let lyrics {
                Text(lyrics)
                    .font(.system(size: 17, weight: .medium))
                    .lineSpacing(7)
                    .foregroundColor(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("Für diesen Titel gibt es keinen Songtext.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke))
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Als Nächstes")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                if !player.upcoming.isEmpty {
                    Button { showQueue = true } label: {
                        Text("Bearbeiten")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.accent)
                    }
                }
            }
            let items = player.upcoming
            if items.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.accent)
                    Text("Vorschläge werden geladen …").foregroundColor(Theme.text2)
                }
                .font(.system(size: 14))
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(items.prefix(30)) { entry in
                        Button { player.playAt(entry.index) } label: {
                            ListRow(item: entry.item)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    static func format(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
