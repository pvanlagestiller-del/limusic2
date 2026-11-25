import SwiftUI
import WebKit
import MediaPlayer
import AVFoundation
import CoreImage

/// Steuert die Wiedergabe: ein einziger versteckter YouTube-Player (WKWebView),
/// eigene Warteschlange, Sperrbildschirm, Bild-in-Bild.
@MainActor
final class PlayerController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = PlayerController()

    @Published private(set) var current: MediaItem?
    @Published private(set) var queue: [MediaItem] = []
    @Published private(set) var index = 0
    @Published var isPlaying = false
    let clock = PlayerClock()
    var time: Double {
        get { clock.time }
        set { if clock.time != newValue { clock.time = newValue } }
    }
    var duration: Double {
        get { clock.duration }
        set { if clock.duration != newValue { clock.duration = newValue } }
    }
    @Published var isAd = false
    @Published var isPiP = false
    @Published var isCC = false
    @Published private(set) var isFullscreen = false
    /// Titel ist geladen, aber der Player ist leer (Ende ohne Autoplay oder nach App-Start)
    private var needsReload = false
    @Published var notice: String?

    struct ChannelState: Equatable {
        let id: String
        var subscribed: Bool
        let name: String
    }
    @Published private(set) var channel: ChannelState?
    @Published private(set) var subscribeBusy = false
    @Published private(set) var details: VideoDetails?
    @Published private(set) var speed: Double = 1
    @Published private(set) var quality = ""
    @Published private(set) var qualities: [String] = []

    /// Kanalseite des laufenden Videos
    var channelRoute: Route? {
        guard let ch = channel else { return nil }
        let stub = MediaItem(id: "c:\(ch.id)", kind: .collection(ch.id), title: ch.name.isEmpty ? "Kanal" : ch.name,
                             subtitle: "Kanal", thumbnail: nil, duration: nil, progress: nil, isMusic: false)
        return .collection(stub)
    }
    private var usingMusicHost = false
    private var stallTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    @Published var isExpanded = false
    /// true = Video zeigen, false = Cover (nur bei Musik ohne Video)
    @Published var videoMode = true

    enum RepeatMode { case off, all, one }
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var shuffle = false
    private var unshuffled: [MediaItem]?
    @Published var coverColor: Color = Theme.accentDeep
    @Published private(set) var sleepUntil: Date?
    private var sleepTask: Task<Void, Never>?

    let webView: WKWebView
    private var artwork: MPMediaItemArtwork?
    private var loadingRelated = false
    private var wasPlayingBeforeBackground = false

    struct UpNext: Identifiable {
        let index: Int
        let item: MediaItem
        var id: String { "\(index)-\(item.id)" }
    }

    var upcoming: [UpNext] {
        queue.indices.filter { $0 > index }.map { UpNext(index: $0, item: queue[$0]) }
    }

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.applicationNameForUserAgent = Scripts.safariSuffix
        if #available(iOS 16.4, *) { config.preferences.isElementFullscreenEnabled = true }
        Scripts.installPlayer(into: config.userContentController)

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: config)
        super.init()

        config.userContentController.add(MessageProxy(self), name: "limusic")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) { webView.isInspectable = true }

        setupRemoteCommands()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        nc.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
        restoreQueue()
    }

    // MARK: Wiedergabe

    func play(_ item: MediaItem, in list: [MediaItem] = []) {
        guard item.videoId != nil else { return }
        var q = list.filter { $0.videoId != nil }
        var i = q.firstIndex(of: item) ?? -1
        if i < 0 { q = [item]; i = 0 }
        queue = q
        index = i
        start()
        if queue.count - index < 4 { extendQueue() }
    }

    /// Spielt den Titel und füllt die Warteschlange mit einem Radio in seinem Stil
    func playRadio(_ item: MediaItem) {
        guard item.videoId != nil else { return }
        unshuffled = nil
        shuffle = false
        queue = [item]
        index = 0
        start()
        extendQueue()
    }

    func playNext(_ item: MediaItem) {
        guard item.videoId != nil else { return }
        guard current != nil else { play(item); return }
        queue.insert(item, at: min(index + 1, queue.count))
    }

    func enqueue(_ item: MediaItem) {
        guard item.videoId != nil else { return }
        guard current != nil else { play(item); return }
        queue.append(item)
    }

    /// Sleep-Timer: nach X Minuten pausieren (nil = aus)
    func setSleep(minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        guard let minutes else { sleepUntil = nil; return }
        sleepUntil = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.cmd("pause")
            self.isPlaying = false
            self.sleepUntil = nil
            self.sleepTask = nil
        }
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func toggleShuffle() {
        if !shuffle {
            unshuffled = queue
            if queue.indices.contains(index) {
                var rest = Array(queue[(index + 1)...])
                rest.shuffle()
                queue = Array(queue[...index]) + rest
            }
            shuffle = true
        } else {
            if let orig = unshuffled {
                let extra = queue.filter { !orig.contains($0) }
                let restored = orig + extra
                if let cur = current, let pos = restored.firstIndex(of: cur) {
                    queue = restored
                    index = pos
                }
            }
            unshuffled = nil
            shuffle = false
        }
    }

    func moveUpcoming(from: IndexSet, to: Int) {
        guard queue.indices.contains(index) else { return }
        var up = Array(queue[(index + 1)...])
        up.move(fromOffsets: from, toOffset: to)
        queue = Array(queue[...index]) + up
    }

    func removeUpcoming(at offsets: IndexSet) {
        guard queue.indices.contains(index) else { return }
        var up = Array(queue[(index + 1)...])
        up.remove(atOffsets: offsets)
        queue = Array(queue[...index]) + up
    }

    private var autoplay: Bool {
        UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true
    }

    private func holdAtEnd() {
        needsReload = true
        isPlaying = false
        stallTask?.cancel()
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        updateNowPlaying()
    }

    // Warteschlange merken, damit sie nach einem App-Neustart wieder da ist

    private struct SavedQueue: Codable {
        var tracks: [SavedTrack]
        var index: Int
    }

    private func persistQueue() {
        guard queue.indices.contains(index) else { return }
        let from = max(0, index - 5)
        let to = min(queue.count, index + 40)
        let saved = SavedQueue(tracks: queue[from..<to].map { SavedTrack($0) }, index: index - from)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "savedQueue")
        }
    }

    private func restoreQueue() {
        guard let data = UserDefaults.standard.data(forKey: "savedQueue"),
              let saved = try? JSONDecoder().decode(SavedQueue.self, from: data),
              saved.tracks.indices.contains(saved.index) else { return }
        queue = saved.tracks.map { $0.item }
        index = saved.index
        current = queue[index]
        videoMode = !queue[index].isMusic || queue[index].hasVideo
        needsReload = true
        isPlaying = false
        loadArtwork()
    }

    private func handleEnded() {
        if repeatMode == .one {
            seek(to: 0)
            cmd("play")
            return
        }
        if index + 1 >= queue.count && repeatMode == .all && !queue.isEmpty {
            index = 0
            start()
            return
        }
        if !autoplay {
            holdAtEnd()
            return
        }
        next()
    }

    func playAt(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        start()
        if queue.count - index < 4 { extendQueue() }
    }

    func next() {
        if index + 1 < queue.count {
            index += 1
            start()
            if queue.count - index < 4 { extendQueue() }
        } else {
            extendQueue(thenPlay: true)
        }
    }

    func previous() {
        if time > 5 || index == 0 { seek(to: 0) } else { index -= 1; start() }
    }

    func toggle() {
        if needsReload {
            start()
            return
        }
        cmd(isPlaying ? "pause" : "play")
        isPlaying.toggle()
        updateNowPlaying()
    }

    func seek(to t: Double) {
        webView.evaluateJavaScript("window.__lmCmd && window.__lmCmd('seek', \(t))", completionHandler: nil)
        time = t
    }

    func togglePiP() { cmd("pip") }

    /// Natives iOS-Vollbild (mit Drehen ins Querformat)
    func enterFullscreen() {
        guard current != nil, videoMode, !isPiP else { return }
        cmd("fs")
    }

    @objc private func orientationChanged() {
        let autoFS = UserDefaults.standard.object(forKey: "autoFullscreen") as? Bool ?? true
        guard autoFS, UIDevice.current.orientation.isLandscape,
              isExpanded, videoMode, current != nil, !isFullscreen, !isPiP else { return }
        enterFullscreen()
    }

    func toggleCC() {
        cmd(isCC ? "ccOff" : "ccOn")
        isCC.toggle()
    }

    func stop() {
        UserDefaults.standard.removeObject(forKey: "savedQueue")
        needsReload = false
        stallTask?.cancel()
        setSleep(minutes: nil)
        cmd("pause")
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isExpanded = false
            current = nil
        }
        queue = []
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    var watchURL: URL? {
        guard let vid = current?.videoId else { return nil }
        return URL(string: "https://\(usingMusicHost ? "music.youtube.com" : "m.youtube.com")/watch?v=\(vid)")
    }

    /// Erst über m.youtube.com, bei Fehler über music.youtube.com
    /// (manche Hörspiele/Songs gibt es nur bei YouTube Music).
    private func start(musicHost: Bool = false) {
        let host = musicHost ? "music.youtube.com" : "m.youtube.com"
        guard queue.indices.contains(index), let vid = queue[index].videoId,
              let url = URL(string: "https://\(host)/watch?v=\(vid)") else { return }
        usingMusicHost = musicHost
        needsReload = false
        current = queue[index]
        videoMode = !queue[index].isMusic || queue[index].hasVideo
        time = 0
        duration = 0
        isAd = false
        isPlaying = true
        try? AVAudioSession.sharedInstance().setActive(true)
        webView.load(URLRequest(url: url))
        loadArtwork()
        updateNowPlaying()
        watchForStall()
        loadChannel()
        persistQueue()
    }

    private func loadChannel() {
        channel = nil
        details = nil
        guard let vid = current?.videoId else { return }
        let expected = current?.id
        Task {
            guard let d = await InnerTube.shared.videoDetails(videoId: vid), current?.id == expected else { return }
            details = d
            // Herz zeigt denselben Stand wie der Daumen bei YouTube
            if d.likeStatus == .like, let c = current { LocalLibrary.shared.setLocal(c, liked: true) }
            if let cid = d.channelId {
                channel = ChannelState(id: cid, subscribed: d.subscribed, name: d.channelName)
            }
        }
    }

    /// Herz wurde getippt: Daumen-Anzeige des laufenden Videos nachziehen
    func noteLike(videoId: String, liked: Bool) {
        guard current?.videoId == videoId, var d = details else { return }
        d.likeStatus = liked ? .like : .none
        details = d
    }

    /// Daumen hoch/runter (nochmal tippen nimmt die Bewertung zurück)
    func setLikeStatus(_ target: VideoDetails.LikeStatus) async {
        guard let vid = current?.videoId, var d = details else { return }
        let new: VideoDetails.LikeStatus = d.likeStatus == target ? .none : target
        let action = new == .like ? "like" : (new == .dislike ? "dislike" : "removelike")
        do {
            try await InnerTube.shared.rate(videoId: vid, action)
            d.likeStatus = new
            if details != nil, current?.videoId == vid { details = d }
            if let c = current, c.videoId == vid { LocalLibrary.shared.setLocal(c, liked: new == .like) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            showNotice("Bewerten hat nicht geklappt – bist du angemeldet?")
        }
    }

    func addToYouTubePlaylist(_ playlistId: String, name: String, item: MediaItem? = nil) async {
        guard let vid = (item ?? current)?.videoId else { return }
        do {
            try await InnerTube.shared.addToPlaylist(playlistId, videoId: vid)
            Feeds.clearCache()
            showNotice("Zu „\(name)“ hinzugefügt")
        } catch {
            showNotice("Hinzufügen hat nicht geklappt – bist du angemeldet?")
        }
    }

    func setSpeed(_ s: Double) {
        speed = s
        webView.evaluateJavaScript("window.__lmRate = \(s); (function(){var v=document.querySelector('video'); if(v){v.playbackRate=\(s);}})();",
                                   completionHandler: nil)
    }

    func setQuality(_ q: String) {
        webView.evaluateJavaScript("window.__lmCmd && window.__lmCmd('quality', '\(q)')", completionHandler: nil)
    }

    /// Zum vorherigen Titel (für Shorts: ohne „an den Anfang springen“)
    func skipBack() {
        guard index > 0 else { return }
        index -= 1
        start()
    }

    func toggleSubscribe() async {
        guard var ch = channel, !subscribeBusy else { return }
        subscribeBusy = true
        let target = !ch.subscribed
        do {
            try await InnerTube.shared.setSubscribed(channelId: ch.id, target)
            ch.subscribed = target
            channel = ch
            Feeds.clearCache()
            let who = ch.name.isEmpty ? "Kanal" : ch.name
            showNotice(target ? "\(who) abonniert" : "Abo von \(who) beendet")
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            showNotice("Abonnieren hat nicht geklappt – bist du angemeldet?")
        }
        subscribeBusy = false
    }

    /// Startet nach 12 Sekunden nichts, gilt der Titel als nicht abspielbar.
    private func watchForStall() {
        stallTask?.cancel()
        let id = current?.id
        let host = usingMusicHost
        stallTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, let self, self.current?.id == id, self.usingMusicHost == host,
                  self.time < 0.5, !self.isAd, !self.isFullscreen, !self.isPiP else { return }
            self.handlePlaybackError()
        }
    }

    private func handlePlaybackError() {
        guard let c = current else { return }
        if !usingMusicHost {
            start(musicHost: true)
            return
        }
        showNotice("„\(c.title)“ lässt sich nicht abspielen – nächster Titel")
        if index + 1 < queue.count || !queue.isEmpty { next() }
    }

    func showNotice(_ text: String) {
        noticeTask?.cancel()
        withAnimation { notice = text }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.notice = nil }
        }
    }

    private func cmd(_ c: String) {
        webView.evaluateJavaScript("window.__lmCmd && window.__lmCmd('\(c)')", completionHandler: nil)
    }

    private func extendQueue(thenPlay: Bool = false) {
        guard !loadingRelated, let last = queue.last, let vid = last.videoId else { return }
        loadingRelated = true
        Task {
            let more = await Feeds.related(videoId: vid, music: last.isMusic)
            loadingRelated = false
            // Warteschlange wurde inzwischen ersetzt: Ergebnis verwerfen und neu laden
            guard queue.last?.videoId == vid else {
                if queue.count - index < 4 { extendQueue(thenPlay: thenPlay) }
                return
            }
            let known = Set(queue.compactMap { $0.videoId })
            var titles = Set(queue.map { $0.title.lowercased() })
            let fresh = more.filter { item in
                guard let v = item.videoId, !known.contains(v) else { return false }
                // andere Versionen desselben Titels überspringen
                return titles.insert(item.title.lowercased()).inserted
            }
            queue.append(contentsOf: fresh)
            if thenPlay, index + 1 < queue.count {
                index += 1
                start()
            }
        }
    }

    // MARK: Nachrichten aus der Seite

    func handle(_ body: Any) {
        guard let m = body as? [String: Any], let type = m["type"] as? String else { return }
        switch type {
        case "state":
            let playing = (m["playing"] as? Bool) ?? false
            let ad = (m["ad"] as? Bool) ?? false
            let pip = (m["pip"] as? Bool) ?? false
            if isPlaying != playing { isPlaying = playing }
            if isAd != ad { isAd = ad }
            if isPiP != pip { isPiP = pip }
            let fs = (m["fs"] as? Bool) ?? false
            if !fs {
                if isFullscreen { isFullscreen = false }
                if OrientationLock.mask != .portrait && UIDevice.current.userInterfaceIdiom != .pad {
                    OrientationLock.set(.portrait, rotateTo: .portrait)
                }
            }
            let q = (m["q"] as? String) ?? ""
            let ql = (m["ql"] as? [String]) ?? []
            if quality != q { quality = q }
            if qualities != ql { qualities = ql }
            let cc = (m["cc"] as? Bool) ?? false
            if isCC != cc { isCC = cc }
            time = (m["time"] as? NSNumber)?.doubleValue ?? 0
            duration = (m["duration"] as? NSNumber)?.doubleValue ?? 0
            updateNowPlaying()
        case "error":
            stallTask?.cancel()
            handlePlaybackError()
        case "pipEnded":
            // WebView einmal neu auslegen, damit das Bild wieder erscheint
            let f = webView.frame
            webView.frame = f.insetBy(dx: 0.5, dy: 0.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.webView.frame = f
            }
        case "fs":
            let on = (m["on"] as? Bool) ?? false
            isFullscreen = on
            if on {
                OrientationLock.set(.allButUpsideDown)
            } else {
                OrientationLock.set(.portrait, rotateTo: .portrait)
            }
        case "ended":
            handleEnded()
        default:
            break
        }
    }

    // MARK: Sperrbildschirm

    private func loadArtwork() {
        artwork = nil
        guard let url = current?.thumbnail else { return }
        let expected = current?.id
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = UIImage(data: data),
                  current?.id == expected else { return }
            artwork = Self.makeArtwork(img)
            let color = Self.dominantColor(img)
            withAnimation(.easeInOut(duration: 0.6)) { coverColor = color }
            updateNowPlaying()
        }
    }

    /// Hauptfarbe des Covers, leicht kräftiger und abgedunkelt
    nonisolated private static func dominantColor(_ img: UIImage) -> Color {
        let fallback = Color(red: 0.690, green: 0.040, blue: 0.140)
        guard let cg = img.cgImage else { return fallback }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let out = filter.outputImage else { return fallback }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8, colorSpace: nil)
        let base = UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(UIColor(hue: h, saturation: max(s, 0.5), brightness: min(max(b, 0.35), 0.6), alpha: 1))
    }

    nonisolated private static func makeArtwork(_ img: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    }

    private func updateNowPlaying() {
        guard let c = current else { return }
        var np: [String: Any] = [
            MPMediaItemPropertyTitle: c.title,
            MPMediaItemPropertyArtist: c.subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 { np[MPMediaItemPropertyPlaybackDuration] = duration }
        if let a = artwork { np[MPMediaItemPropertyArtwork] = a }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = np
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.needsReload { self.start() } else { self.cmd("play") }
            }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.cmd("pause") }; return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }; return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }; return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }; return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in self?.seek(to: t) }
            return .success
        }
    }

    // MARK: Hintergrund

    @objc private func willResignActive() {
        wasPlayingBeforeBackground = isPlaying
        let autoPiP = UserDefaults.standard.object(forKey: "autoPiP") as? Bool ?? true
        if autoPiP, isPlaying, current != nil, videoMode {
            cmd("pipOn")
        }
    }

    @objc private func didEnterBackground() {
        guard wasPlayingBeforeBackground else { return }
        for delay in [0.4, 1.2, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.cmd("play")
            }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(WebPolicy.decide(navigationAction))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if Scripts.adblockEnabled, !Scripts.engineJS.isEmpty {
            webView.evaluateJavaScript(Scripts.engineJS, completionHandler: nil)
        }
        if speed != 1 {
            webView.evaluateJavaScript("window.__lmRate = \(speed);", completionHandler: nil)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if current != nil { start() }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }
}

/// Verhindert Retain-Zyklus WKUserContentController -> PlayerController
final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: PlayerController?
    init(_ target: PlayerController) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        let t = target
        Task { @MainActor in t?.handle(body) }
    }
}

/// Gemeinsame Navigationsregeln für alle WebViews.
@MainActor
enum WebPolicy {
    private static let allowedSuffixes = [
        "youtube.com", "youtu.be", "ytimg.com", "googlevideo.com", "google.com", "google.de",
        "gstatic.com", "googleusercontent.com", "youtube-nocookie.com"
    ]

    /// .allow + 2 = „erlauben, aber nicht an installierte Apps (YouTube/YouTube Music) weiterreichen“
    static let allowWithoutAppLink =
        WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow

    static func decide(_ action: WKNavigationAction) -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .allow }
        let scheme = url.scheme?.lowercased() ?? ""
        if !["http", "https", "about", "blob", "data"].contains(scheme) { return .cancel }
        let isMain = action.targetFrame?.isMainFrame ?? true
        if isMain, let host = url.host?.lowercased(),
           !allowedSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            UIApplication.shared.open(url)
            return .cancel
        }
        return allowWithoutAppLink
    }
}

/// Bindet den einen Player-WebView in SwiftUI ein.
struct PlayerWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        let web = PlayerController.shared.webView
        web.removeFromSuperview()
        web.frame = container.bounds
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(web)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Laufzeit getrennt vom Rest, damit nur die Player-Ansichten im Halbsekundentakt neu zeichnen.
@MainActor
final class PlayerClock: ObservableObject {
    @Published var time: Double = 0
    @Published var duration: Double = 0
}
