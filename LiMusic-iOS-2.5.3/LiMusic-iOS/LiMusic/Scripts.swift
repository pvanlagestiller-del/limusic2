import WebKit

/// Seiten-Skripte: LiMusic-Anti-AD-Engine, Hintergrundwiedergabe, Player-Steuerung.
enum Scripts {

    static let safariSuffix = "Version/18.0 Mobile/15E148 Safari/604.1"

    static var adblockEnabled: Bool {
        UserDefaults.standard.object(forKey: "adblock") as? Bool ?? true
    }

    // MARK: Anti-AD (Engine 1.1 aus der Linux-Version)

    private static let ruleListID = "limusic-antiad-engine-1.1"

    static let engineJS: String = {
        if let js = try? String(contentsOf: FilterUpdater.jsURL, encoding: .utf8), js.contains("__limusic") {
            return js
        }
        guard let url = Bundle.main.url(forResource: "antiad", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("LiMusic: antiad.js fehlt im Bundle")
            return ""
        }
        return js
    }()

    static func contentRuleList(_ completion: @escaping (WKContentRuleList?) -> Void) {
        guard let store = WKContentRuleListStore.default() else { return completion(nil) }
        let bundled = Bundle.main.url(forResource: "antiad-filter", withExtension: "json")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let remote = try? String(contentsOf: FilterUpdater.jsonURL, encoding: .utf8)

        func compile(_ json: String?, id: String, fallback: String?) {
            guard let json else { return DispatchQueue.main.async { completion(nil) } }
            store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { list, error in
                if let error {
                    NSLog("LiMusic: Filterliste fehlerhaft: \(error)")
                    if fallback != nil { return compile(fallback, id: ruleListID, fallback: nil) }
                }
                DispatchQueue.main.async { completion(list) }
            }
        }

        if let remote {
            compile(remote, id: "limusic-antiad-remote", fallback: bundled)
        } else {
            compile(bundled, id: ruleListID, fallback: nil)
        }
    }

    // MARK: Einbau

    /// Versteckter Player (m.youtube.com/watch)
    static func installPlayer(into ucc: WKUserContentController) {
        ucc.addUserScript(WKUserScript(source: visibilityJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        addEngine(to: ucc)
        ucc.addUserScript(WKUserScript(source: consentJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: playerJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        addRuleList(to: ucc)
    }

    /// Klassische Web-Ansicht (Notlösung)
    static func installClassic(into ucc: WKUserContentController) {
        ucc.addUserScript(WKUserScript(source: visibilityJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        addEngine(to: ucc)
        ucc.addUserScript(WKUserScript(source: consentJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        addRuleList(to: ucc)
    }

    private static func addEngine(to ucc: WKUserContentController) {
        guard adblockEnabled, !engineJS.isEmpty else { return }
        ucc.addUserScript(WKUserScript(source: engineJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: engineJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    private static func addRuleList(to ucc: WKUserContentController) {
        guard adblockEnabled else { return }
        contentRuleList { list in if let list { ucc.add(list) } }
    }

    // MARK: Skripte

    /// Seite gilt immer als sichtbar -> YouTube pausiert nicht im Hintergrund.
    private static let visibilityJS = #"""
    (function () {
      'use strict';
      if (window.__limusicVis) return; window.__limusicVis = true;
      try {
        Object.defineProperty(Document.prototype, 'hidden', { get: () => false, configurable: true });
        Object.defineProperty(Document.prototype, 'visibilityState', { get: () => 'visible', configurable: true });
        Object.defineProperty(Document.prototype, 'webkitHidden', { get: () => false, configurable: true });
      } catch (e) {}
      const stop = (e) => e.stopImmediatePropagation();
      document.addEventListener('visibilitychange', stop, true);
      document.addEventListener('webkitvisibilitychange', stop, true);
    })();
    """#

    /// Cookie-Zustimmungsseite (EU) automatisch mit "Alle ablehnen" schließen.
    private static let consentJS = #"""
    (function () {
      if (!/^consent\./.test(location.host)) return;
      const tryClick = () => {
        const btns = Array.from(document.querySelectorAll('button, input[type=submit]'));
        const b = btns.find((x) => /alle ablehnen|reject all/i.test(x.textContent || x.value || ''));
        if (b) { b.click(); return true; }
        return false;
      };
      if (!tryClick()) { let n = 0; const t = setInterval(() => { if (tryClick() || ++n > 20) clearInterval(t); }, 300); }
    })();
    """#

    /// Player-Seite: nur das Video zeigen, Zustand melden, Befehle annehmen.
    private static let playerJS = #"""
    (function () {
      'use strict';
      if (window.__lmPlayer) return; window.__lmPlayer = true;
      if (!/youtube\.com$/.test(location.host)) return;

      const post = (m) => { try { window.webkit.messageHandlers.limusic.postMessage(m); } catch (e) {} };
      const CSS = `
        html, body { background: #000 !important; overflow: hidden !important;
                     width: 100vw !important; max-width: 100vw !important; }
        #player-container-id, #player, #movie_player, .html5-video-player {
          position: fixed !important; inset: 0 !important; width: 100vw !important; height: 100vh !important;
          max-height: none !important; z-index: 2147483646 !important; background: #000 !important;
          transform: none !important; margin: 0 !important; padding: 0 !important;
        }
        video { width: 100vw !important; height: 100vh !important; left: 0 !important; top: 0 !important;
                object-fit: contain !important; }
        ytm-mobile-topbar-renderer, #header-bar, ytm-pivot-bar-renderer, .player-controls-background-container,
        .player-controls-content, #player-control-overlay, ytm-custom-control, .ytm-autonav-bar,
        .ytp-unmute, .ytp-chrome-bottom, .ytp-chrome-top, .ytp-gradient-bottom, .ytp-gradient-top,
        ytm-single-column-watch-next-results-renderer, ytm-mealbar-promo-renderer, .mealbar-promo-renderer,
        ytm-consent-bump-v2-renderer, ytmusic-nav-bar, ytmusic-player-bar, ytmusic-mealbar-promo-renderer,
        tp-yt-paper-dialog, ytmusic-popup-container { display: none !important; }
        ytmusic-player, #song-video, #song-media-window {
          position: fixed !important; inset: 0 !important; width: 100vw !important; height: 100vh !important;
          z-index: 2147483645 !important; background: #000 !important; margin: 0 !important;
        }
      `;
      function applyStyle() {
        if (document.getElementById('lm-player-style')) return;
        const st = document.createElement('style');
        st.id = 'lm-player-style';
        st.textContent = CSS;
        (document.head || document.documentElement).appendChild(st);
      }

      window.__lmWantPlay = true;
      const isAd = () => !!document.querySelector('.ad-showing, .ad-interrupting');
      let lastVideo = null;
      let endedSent = false;
      let mutedByUs = false;

      let errorSent = false;
      function tick() {
        applyStyle();
        const err = document.querySelector(
          '.ytp-error, ytm-player-error-message-renderer, .player-error-message-container, ' +
          'yt-playability-error-supported-renderers, ytmusic-player-error-message-renderer');
        if (err && err.offsetParent !== null && !errorSent) {
          errorSent = true;
          post({ type: 'error', host: location.host });
        }
        const v = document.querySelector('video');
        if (!v) return;
        if (v !== lastVideo) {
          lastVideo = v; endedSent = false;
          v.addEventListener('ended', () => {
            if (!endedSent && !isAd()) { endedSent = true; post({ type: 'ended' }); }
          });
          // Nur echtes Vollbild melden. iOS feuert die Vollbild-Ereignisse auch beim
          // Wechsel ins schwebende Fenster (Bild-in-Bild) – das darf hier nichts auslösen.
          let fsOn = false;
          const syncFs = () => {
            const full = v.webkitPresentationMode === 'fullscreen';
            if (full && !fsOn) {
              fsOn = true;
              post({ type: 'fs', on: true });
            } else if (!full && fsOn) {
              fsOn = false;
              post({ type: 'fs', on: false });
              if (window.__lmWantPlay) setTimeout(() => v.play().catch(() => {}), 300);
            }
          };
          v.addEventListener('webkitpresentationmodechanged', syncFs);
          let lastMode = v.webkitPresentationMode;
          v.addEventListener('webkitpresentationmodechanged', () => {
            const mode = v.webkitPresentationMode;
            if (lastMode === 'picture-in-picture' && mode === 'inline') {
              // Video-Ebene nach dem Zurückholen neu aufbauen, sonst bleibt sie grau
              const t = v.style.transform;
              v.style.transform = 'translateZ(0)';
              requestAnimationFrame(() => { v.style.transform = t; });
              post({ type: 'pipEnded' });
              if (window.__lmWantPlay) setTimeout(() => v.play().catch(() => {}), 250);
            }
            lastMode = mode;
          });
          v.addEventListener('webkitbeginfullscreen', syncFs);
          v.addEventListener('webkitendfullscreen', syncFs);
        }
        const ad = isAd();
        if (ad) {
          if (!v.muted) { v.muted = true; mutedByUs = true; }
          try { v.playbackRate = 16; } catch (e) {}
          if (isFinite(v.duration) && v.duration > 0) v.currentTime = v.duration;
          document.querySelectorAll('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, ytm-skip-ad-button button')
            .forEach((b) => { try { b.click(); } catch (e) {} });
        } else {
          // YouTube startet auf dem Handy stumm (Autoplay) – Ton einschalten
          if (v.muted || mutedByUs) {
            v.muted = false;
            try { const mp = document.getElementById('movie_player'); if (mp && mp.unMute) { mp.unMute(); mp.setVolume && mp.setVolume(100); } } catch (e) {}
          }
          if (v.volume < 1) v.volume = 1;
          mutedByUs = false;
          if (v.playbackRate > 2) v.playbackRate = 1;
          const want = window.__lmRate;
          if (want && Math.abs(v.playbackRate - want) > 0.01) { try { v.playbackRate = want; } catch (e) {} }
        }
        if (window.__lmWantPlay && v.paused && !v.ended) v.play().catch(() => {});
        let q = '', ql = [];
        try {
          const mp = document.getElementById('movie_player');
          if (mp && mp.getPlaybackQuality) {
            q = mp.getPlaybackQuality() || '';
            ql = (mp.getAvailableQualityLevels && mp.getAvailableQualityLevels()) || [];
          }
        } catch (e) {}
        post({
          type: 'state',
          playing: !v.paused,
          time: v.currentTime || 0,
          duration: isFinite(v.duration) ? v.duration : 0,
          ad: ad,
          pip: v.webkitPresentationMode === 'picture-in-picture',
          cc: ccOn(),
          fs: v.webkitPresentationMode === 'fullscreen',
          q: q,
          ql: ql
        });
      }
      setInterval(tick, 500);

      function ccOn() {
        try {
          const mp = document.getElementById('movie_player');
          if (mp && mp.isSubtitlesOn) return !!mp.isSubtitlesOn();
        } catch (e) {}
        const cap = document.querySelector('.ytp-caption-window-container .caption-window, .captions-text');
        return !!cap;
      }

      function setCC(on) {
        const mp = document.getElementById('movie_player');
        if (!mp) return;
        try {
          if (mp.toggleSubtitles && mp.isSubtitlesOn) {
            if (!!mp.isSubtitlesOn() !== on) mp.toggleSubtitles();
            return;
          }
        } catch (e) {}
        try {
          if (on) {
            mp.loadModule && mp.loadModule('captions');
          } else {
            mp.unloadModule && mp.unloadModule('captions');
          }
        } catch (e) {}
      }

      window.__lmCmd = function (c, arg) {
        const v = document.querySelector('video');
        if (!v) return;
        switch (c) {
          case 'play': window.__lmWantPlay = true; v.play().catch(() => {}); break;
          case 'pause': window.__lmWantPlay = false; v.pause(); break;
          case 'seek': v.currentTime = arg; break;
          case 'quality':
            try {
              const mp = document.getElementById('movie_player');
              if (mp && mp.setPlaybackQualityRange) mp.setPlaybackQualityRange(arg, arg);
              if (mp && mp.setPlaybackQuality) mp.setPlaybackQuality(arg);
            } catch (e) {}
            break;
          case 'ccOn': setCC(true); break;
          case 'ccOff': setCC(false); break;
          case 'fs':
            try {
              if (v.webkitEnterFullscreen) { v.webkitEnterFullscreen(); }
              else if (v.requestFullscreen) { v.requestFullscreen(); }
            } catch (e) {}
            break;
          case 'pip': {
            const on = v.webkitPresentationMode === 'picture-in-picture' || !!document.pictureInPictureElement;
            if (on) {
              try { if (document.pictureInPictureElement) document.exitPictureInPicture(); } catch (e) {}
              try { v.webkitSetPresentationMode('inline'); } catch (e) {}
            } else {
              try { v.webkitSetPresentationMode('picture-in-picture'); }
              catch (e) { try { v.requestPictureInPicture(); } catch (e2) {} }
            }
            break;
          }
          case 'pipOn':
            if (v.webkitPresentationMode !== 'picture-in-picture') {
              try { v.webkitSetPresentationMode('picture-in-picture'); } catch (e) {}
            }
            break;
        }
        tick();
      };
    })();
    """#
}

/// Holt neue Werbefilter aus einem öffentlichen Ordner (z. B. GitHub raw).
/// Wirkt beim nächsten Start der App.
enum FilterUpdater {
    static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("filters", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static var jsURL: URL { dir.appendingPathComponent("antiad.js") }
    static var jsonURL: URL { dir.appendingPathComponent("antiad-filter.json") }
    static var baseURL: String { UserDefaults.standard.string(forKey: "filterURL") ?? "" }
    static var lastUpdate: Date? { UserDefaults.standard.object(forKey: "filterUpdated") as? Date }

    @discardableResult
    static func update() async -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty,
              let ju = URL(string: base + "/antiad.js"),
              let fu = URL(string: base + "/antiad-filter.json") else {
            return "Keine Filter-Adresse eingetragen."
        }
        do {
            var r1 = URLRequest(url: ju); r1.cachePolicy = .reloadIgnoringLocalCacheData
            var r2 = URLRequest(url: fu); r2.cachePolicy = .reloadIgnoringLocalCacheData
            let (js, resp1) = try await URLSession.shared.data(for: r1)
            let (json, resp2) = try await URLSession.shared.data(for: r2)
            guard (resp1 as? HTTPURLResponse)?.statusCode == 200,
                  (resp2 as? HTTPURLResponse)?.statusCode == 200 else {
                return "Dateien nicht gefunden – Adresse prüfen (Repo muss öffentlich sein)."
            }
            guard let text = String(data: js, encoding: .utf8), text.contains("__limusic"),
                  (try? JSONSerialization.jsonObject(with: json)) is [Any] else {
                return "Dateien ungültig – nichts geändert."
            }
            try js.write(to: jsURL, options: .atomic)
            try json.write(to: jsonURL, options: .atomic)
            UserDefaults.standard.set(Date(), forKey: "filterUpdated")
            return "Filter geladen – wirkt nach Neustart der App."
        } catch {
            return "Aktualisierung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    static func reset() {
        try? FileManager.default.removeItem(at: jsURL)
        try? FileManager.default.removeItem(at: jsonURL)
        UserDefaults.standard.removeObject(forKey: "filterUpdated")
    }
}
