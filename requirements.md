# Projekt-Requirements: BLE Device Scanner App (iOS 26 / 27 mit GitHub CI/CD & automatisierter Signierung)

## 1. Projekt-Überblick & Zielsetzung
Erstelle ein vollständiges, sofort lauffähiges iOS-Projekt als "Hello World"-App. Die App zeigt alle derzeit per Bluetooth Low Energy (BLE) verbundenen oder in der Nähe befindlichen Geräte an. 
Das Projekt muss so strukturiert und vorbereitet werden, dass es direkt als **GitHub-Repository** versioniert und über **GitHub Actions** vollständig in der Cloud (auf einem macOS-Runner) kompiliert und signiert werden kann.

---

## 2. Technische Rahmenbedingungen & Plattformen
- **Zielplattform:** iOS (iPhone)
- **Kompatibilität:** Voll funktionsfähig und getestet für **iOS 26 und iOS 27**.
- **Programmiersprache & Paradigma:** **100% nativ in Swift** implementiert (unter Verwendung moderner Swift-Konstrukte, z.B. `@Observable` oder aktuelle State-Management-Ansätze).
- **Frameworks:** Ausschließlich native Apple-Frameworks verwenden: **SwiftUI** (für die Benutzeroberfläche) und **CoreBluetooth** (für die BLE-Funktionalität).
- **Abhängigkeiten:** **Keine** externen Bibliotheken oder Drittanbieter-Frameworks (kein CocoaPods, kein Swift Package Manager mit externen Dependencies).
- **Architektur:** Sauberer MVVM-Ansatz (Model-View-ViewModel).
- **Vorbereitung für Versionskontrolle:** Das Projekt muss eine saubere `.gitignore`-Datei für Swift/Xcode enthalten (Ausschluss von `DerivedData`, `xcuserdata` etc.).

---

## 3. Funktionale Anforderungen (App-Logik)

### 3.1. Benutzeroberfläche (UI / SwiftUI)
- **Hauptansicht (`ContentView`):** 
  - Liste (`List`) zur Anzeige gefundener BLE-Geräte (Name, UUID, RSSI-Signalstärke).
- **Steuerungselemente:**
  - "Scan starten / stoppen"-Button sowie Ladeindikator.

### 3.2. Bluetooth-Logik (CoreBluetooth)
- **Central Manager:** Implementierung von `CBCentralManager` im ViewModel.
- **Berechtigungen:** 
  - Eintrag in der `Info.plist`: `NSBluetoothAlwaysUsageDescription` (*"Diese App benötigt Bluetooth, um Geräte in Ihrer Umgebung anzuzeigen."*).

---

## 4. GitHub Actions & Automatisierter Cloud-Build (CI/CD)
Der Agent muss im Projekt einen Ordner `.github/workflows/` mit einer Workflow-Datei (z. B. `build-ios.yml`) anlegen, die das automatische Kompilieren bei einem Push in den `main`-Branch übernimmt.

### 4.1. Workflow-Schritte in der GitHub Action
1. **Checkout:** Auschecken des Quellcodes.
2. **Xcode-Version festlegen:** Sicherstellen, dass die passende Xcode-Version auf dem macOS-Runner verwendet wird.
3. **Keychain einrichten:** Erstellen einer temporären Keychain auf dem Cloud-Mac für das Code Signing.
4. **Zertifikate & Provisioning Profile importieren:** Automatisches Entschlüsseln und Installieren des Signing-Zertifikats (`.p12`) und des Provisioning Profils (`.mobileprovision`) über GitHub Secrets.
5. **Xcode Build & Archive:** 
   - Kompilieren des Projekts für physische iPhones (`generic/platform=iOS`).
   - Exportieren als `.ipa`-Datei mithilfe eines ExportOptions-Plists.
6. **Artefakt-Upload:** Bereitstellen der fertigen `.ipa`-Datei als GitHub Actions Artifact zum Herunterladen.

---

## 5. Vollständige Code-Signierung auf GitHub (Anforderungen & Secrets)

Da Apple für den Build zwingend eine Signierung vorschreibt, müssen die dafür notwendigen Mechanismen im Workflow berücksichtigt und im Prompt dokumentiert werden.

### 5.1. Erforderliche GitHub Secrets (müssen im Repository hinterlegt werden)
Der Agent muss im Workflow auf folgende GitHub Secrets verweisen und diese in der Konfiguration nutzen:
- `BUILD_CERTIFICATE_BASE64`: Das Apple-Entwickler-Zertifikat (`.p12`-Datei), umgewandelt in einen Base64-String.
- `P12_PASSWORD`: Das Passwort, mit dem das `.p12`-Zertifikat geschützt ist.
- `BUILD_PROVISION_PROFILE_BASE64`: Das Apple Provisioning Profile (`.mobileprovision`-Datei) für die App-ID, ebenfalls als Base64-String.
- `KEYCHAIN_PASSWORD`: Ein sicheres, temporäres Passwort für die Erstellung der temporären Build-Keychain auf dem Runner.
- `TEAM_ID`: Die Apple Developer Team ID (falls für das Exportieren erforderlich).

### 5.2. Workflow-Skript-Ausschnitt (Beispiel-Logik, die der Agent implementieren soll)
Der Agent soll im Workflow Schritte vorsehen, die:
- Die Base64-Secrets decodieren und lokal auf dem Runner ablegen (`base64 --decode`).
- Eine Keychain erstellen, sie entsperren und das Zertifikat importieren.
- Das Provisioning Profile in den Ordner `~/Library/MobileDevice/Provisioning Profiles` kopieren.
- Den Build-Befehl ausführen:
  ```bash
  xcodebuild -project "Projektname.xcodeproj" \
             -scheme "Projektname" \
             -sdk iphoneos \
             -configuration Release \
             archive -archivePath build/Projektname.xcarchive \
             CODE_SIGN_STYLE="Manual" \
             PROVISIONING_PROFILE_SPECIFIER="Name_des_Profils" \
             DEVELOPMENT_TEAM="TEAM_ID"