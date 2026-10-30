import Foundation

/// A Bluetooth Low Energy peripheral seen by the scanner or reported as connected by the system.
struct BLEDevice: Identifiable, Equatable, Sendable {
    /// iOS-assigned peripheral identifier. Stable per app and device, but not the hardware MAC address.
    let id: UUID
    var name: String?
    /// Signal strength in dBm. `nil` for connected devices that have not been seen in the scan yet.
    var rssi: Int?
    var isConnected: Bool
    var lastSeen: Date

    var displayName: String {
        guard let name, !name.isEmpty else { return "Unbekanntes Gerät" }
        return name
    }

    /// Signal quality mapped to 0...1 (-100 dBm → 0, -40 dBm → 1), used for the signal bars icon.
    var signalQuality: Double {
        guard let rssi else { return 0 }
        return min(max(Double(rssi + 100) / 60, 0), 1)
    }
}
