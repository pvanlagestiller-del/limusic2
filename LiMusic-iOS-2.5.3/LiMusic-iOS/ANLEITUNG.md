# LiMusic 2.0 für iPhone

Eigene Oberfläche im LiMaD-Stil: Startseite, Weiterschauen, Musik-Regale, Entdecken,
Bibliothek, Suche, Mini-Player und Vollbild-Player. Inhalte kommen von YouTube /
YouTube Music (mit deinem Google-Login), Werbung blockiert die LiMusic-Anti-AD-Engine.

## Erster Start

1. Unten **Profil → Mit Google anmelden**. Ohne Anmeldung gibt es nur Suche und Entdecken.
2. Oben zwischen **Videos** und **Musik** umschalten.

## Bedienung

- **Antippen** spielt ab. Alben/Playlists öffnen eine eigene Seite mit „Abspielen“ und „Zufall“.
- **Mini-Player** (über der Leiste): antippen = groß, nach links wischen = nächster Titel.
- **Großer Player**: nach unten wischen = klein. Knöpfe: Schwebend (Bild-in-Bild), Klassisch, Beenden.
- **Player** in der unteren Leiste öffnet den großen Player.
- Startseite **nach unten ziehen** = neu laden.
- Beim Verlassen der App läuft ein Video automatisch als schwebendes Fenster weiter
  (abschaltbar im Profil). Musik läuft im Hintergrund und auf dem Sperrbildschirm weiter.

## Wenn etwas fehlt

YouTube ändert seine Seiten regelmäßig. Dann **Profil → Klassische Ansicht** nutzen und
mir einen Screenshot schicken.

## Bauen

GitHub: Dateien ins Repository hochladen → Actions baut automatisch → unter **Artifacts**
`LiMusic-ipa` laden → `LiMusic.ipa` per SideStore installieren (ersetzt die alte Version,
Daten bleiben erhalten).

Mac: `./build-ipa.sh` → `build/LiMusic.ipa`.
