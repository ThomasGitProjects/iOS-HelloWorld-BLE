# HelloWorldBLEScanner

Native „Hello World“-App für iPhone (iOS 26/27), die Bluetooth-Low-Energy-Geräte in der Nähe und bereits verbundene Geräte auflistet. Es gibt keine externen Abhängigkeiten, nur SwiftUI und CoreBluetooth.

- **Bundle ID:** `test.project.BLEScanner`
- **Deployment Target:** iOS 26.0 (Swift 6, Xcode 26 oder neuer)
- **Architektur:** MVVM. `BLEDevice` (Model), `BluetoothViewModel` (`@Observable`, kapselt `CBCentralManager`) und `ContentView` (SwiftUI)

Gebaut wird ausschließlich in der Cloud über GitHub Actions ([.github/workflows/build-ios.yml](.github/workflows/build-ios.yml)). Lokal ist kein Mac nötig.

## Funktionsweise

- Die Bluetooth-Berechtigung wird erst beim ersten Tippen auf **Scan starten** abgefragt.
- Die Liste zeigt Name, UUID und RSSI. Sie aktualisiert sich etwa einmal pro Sekunde und Gerät. Geräte, die 30 s nicht gesehen wurden, verschwinden.
- **Verbundene Geräte:** iOS meldet sie nur für bekannte Services. Abgefragt werden Device Information, Battery, HID, Heart Rate und Generic Access. Ein verbundenes Gerät ohne diese Services erscheint nur, wenn es zusätzlich Advertising sendet.
- Die **UUID ist keine MAC-Adresse.** iOS vergibt pro App und Gerät eine eigene Kennung.
- BLE funktioniert im iOS-Simulator nicht. Testen geht nur auf einem echten iPhone.

## CI-Build

Der Workflow startet bei jedem Push auf `main`, bei Pull Requests und manuell (*Actions → Build iOS → Run workflow*).

| Situation | Ergebnis (Artifact) |
|---|---|
| Alle Signier-Secrets hinterlegt | **signierte** `HelloWorldBLEScanner-release-testing-<nr>.ipa` (Ad Hoc) |
| Secrets fehlen (z. B. Fork-PR) | **unsignierte** `HelloWorldBLEScanner-unsigned-<nr>.ipa`. Der Build ist trotzdem grün |

Das Artifact findest du im jeweiligen Workflow-Lauf unter **Artifacts**. Es wird 14 Tage aufbewahrt.

## Code-Signierung (Ad Hoc)

### Voraussetzung

Für eine Signierung in der Pipeline brauchst du eine **Mitgliedschaft im Apple Developer Program** (99 $/Jahr, <https://developer.apple.com/programs/>). Mit einer normalen, kostenlosen Apple ID lassen sich keine Zertifikate und Provisioning Profiles herunterladen. Die erstellt Xcode dann nur lokal auf einem Mac, und sie laufen nach 7 Tagen ab.

### 1. Zertifikat erstellen (geht auch unter Windows, ohne Mac)

OpenSSL ist in Git for Windows enthalten (`C:\Program Files\Git\usr\bin\openssl.exe`). In PowerShell:

```powershell
openssl genrsa -out distribution.key 2048
openssl req -new -key distribution.key -out distribution.certSigningRequest -subj "/emailAddress=deine@mail.at/CN=Dein Name/C=AT"
```

1. <https://developer.apple.com/account/resources/certificates> → **+** → **Apple Distribution** → `distribution.certSigningRequest` hochladen → `distribution.cer` herunterladen.
2. In `.p12` umwandeln und dabei ein Passwort vergeben (das wird `P12_PASSWORD`):

```powershell
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
openssl pkcs12 -export -inkey distribution.key -in distribution.pem -out distribution.p12 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
```

Die Option mit 3DES/SHA1 sorgt dafür, dass macOS (`security import`) die Datei auf dem Runner sicher lesen kann.

### 2. App-ID, Gerät und Provisioning Profile

1. **Identifiers** → **+** → App IDs → App → Bundle ID *explicit* `test.project.BLEScanner`. Capabilities braucht es keine, Bluetooth ist keine Capability.
2. **Devices** → **+**: Die UDID deines iPhones registrieren. Unter Windows: iPhone anschließen, in der App *Apple-Geräte* (oder iTunes) auf die Seriennummer klicken, bis die UDID erscheint.
3. **Profiles** → **+** → **Ad Hoc** → die App-ID, das Distribution-Zertifikat und dein Gerät auswählen → einen Namen vergeben → `.mobileprovision` herunterladen.

Neue Geräte kommen erst in die App, wenn sie im Profil stehen. Danach das Profil neu erzeugen und das Secret aktualisieren.

### 3. GitHub Secrets hinterlegen

*Repository → Settings → Secrets and variables → Actions → New repository secret*

| Secret | Inhalt |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | `distribution.p12` als Base64 |
| `P12_PASSWORD` | Passwort der `.p12` |
| `BUILD_PROVISION_PROFILE_BASE64` | `.mobileprovision` als Base64 |
| `KEYCHAIN_PASSWORD` | beliebiges, zufälliges Passwort für die temporäre Keychain auf dem Runner |
| `TEAM_ID` | Apple Team ID (10 Zeichen, *Membership details*). Optional: Fehlt das Secret, wird die Team ID aus dem Profil gelesen. Ist es gesetzt, wird es mit dem Profil abgeglichen |

Base64 erzeugen und in die Zwischenablage kopieren:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("distribution.p12")) | Set-Clipboard
```

```bash
base64 -i distribution.p12 | pbcopy   # macOS
```

Den Profilnamen, die UUID, das Team und die Export-Methode liest der Workflow automatisch aus dem Provisioning Profile:

- Ad-Hoc-Profil → `release-testing`
- Development-Profil → `debugging`
- App-Store-Profil → `app-store-connect`

Der Workflow bricht mit einer klaren Fehlermeldung ab, wenn Profil und Bundle ID nicht zusammenpassen.

Lösche `.key`, `.p12` und `.mobileprovision` nach dem Hochladen sicher. Die `.gitignore` schließt sie aus, aber sie gehören nicht ins Repository.

## Installation auf dem iPhone

- **Signierte Ad-Hoc-IPA:** Über *Apple Configurator* (Mac) oder ein Windows-Tool wie *3uTools*/*iMazing* installieren, oder über einen Dienst wie Diawi als Link verteilen. Das iPhone muss im Profil registriert sein. Unter iOS 26 muss außerdem der **Entwicklermodus** aktiv sein (*Einstellungen → Datenschutz & Sicherheit → Entwicklermodus*).
- **Unsignierte IPA (ohne Developer Program):** Mit [Sideloadly](https://sideloadly.io) unter Windows und deiner Apple ID signieren und installieren. Mit einer kostenlosen Apple ID läuft die App 7 Tage und muss dann neu signiert werden.
