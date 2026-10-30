import CoreBluetooth
import Foundation
import Observation

/// Owns the `CBCentralManager`, scans for nearby BLE peripherals and exposes them to the UI.
///
/// The central manager is created with the main queue, so every delegate callback already runs on
/// the main thread. The delegate methods are `nonisolated` (CoreBluetooth calls them from Objective-C)
/// and hop back with `MainActor.assumeIsolated`, passing only Sendable values.
@MainActor
@Observable
final class BluetoothViewModel: NSObject {
    private(set) var devices: [UUID: BLEDevice] = [:]
    private(set) var isScanning = false
    private(set) var bluetoothState: CBManagerState = .unknown

    /// Services commonly exposed by connected peripherals (headphones, keyboards, watches, fitness sensors).
    /// iOS only reports connected peripherals for explicitly listed services.
    private static let connectedServiceUUIDs: [CBUUID] = [
        CBUUID(string: "180A"), // Device Information
        CBUUID(string: "180F"), // Battery
        CBUUID(string: "1812"), // Human Interface Device
        CBUUID(string: "180D"), // Heart Rate
        CBUUID(string: "1800"), // Generic Access
    ]

    /// Minimum interval between UI updates for the same device, so the list does not flicker.
    private static let updateInterval: TimeInterval = 1
    /// Devices not seen for this long are removed from the list while scanning.
    private static let staleInterval: TimeInterval = 30

    @ObservationIgnored private var centralManager: CBCentralManager?
    @ObservationIgnored private var scanRequested = false
    @ObservationIgnored private var pruneTask: Task<Void, Never>?

    /// Connected devices first, then by signal strength (strongest first), then by name.
    var sortedDevices: [BLEDevice] {
        devices.values.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
            let lhsRSSI = lhs.rssi ?? Int.min
            let rhsRSSI = rhs.rssi ?? Int.min
            if lhsRSSI != rhsRSSI { return lhsRSSI > rhsRSSI }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// A user-facing explanation when Bluetooth cannot be used, otherwise `nil`.
    var stateMessage: String? {
        switch bluetoothState {
        case .poweredOff: "Bluetooth ist ausgeschaltet. Bitte im Kontrollzentrum oder in den Einstellungen aktivieren."
        case .unauthorized: "Die App hat keinen Zugriff auf Bluetooth. Bitte in den Einstellungen erlauben."
        case .unsupported: "Dieses Gerät unterstützt kein Bluetooth Low Energy."
        case .resetting: "Bluetooth wird neu gestartet …"
        default: nil
        }
    }

    var needsSettings: Bool { bluetoothState == .unauthorized }

    func toggleScan() {
        isScanning ? stopScan() : startScan()
    }

    func startScan() {
        scanRequested = true
        guard let centralManager else {
            // Created lazily so the permission prompt appears only after the user taps "Scan starten".
            // Scanning begins in `handleStateUpdate` once the manager reports `.poweredOn`.
            self.centralManager = CBCentralManager(
                delegate: self,
                queue: nil,
                options: [CBCentralManagerOptionShowPowerAlertKey: true]
            )
            isScanning = true
            return
        }
        isScanning = true
        if centralManager.state == .poweredOn {
            beginScan(with: centralManager)
        }
    }

    func stopScan() {
        scanRequested = false
        isScanning = false
        pruneTask?.cancel()
        pruneTask = nil
        centralManager?.stopScan()
    }

    private func beginScan(with central: CBCentralManager) {
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        refreshConnectedDevices(with: central)
        startPruning()
    }

    private func refreshConnectedDevices(with central: CBCentralManager) {
        let connected = central.retrieveConnectedPeripherals(withServices: Self.connectedServiceUUIDs)
        let connectedIDs = Set(connected.map(\.identifier))
        let now = Date.now

        for id in devices.keys where devices[id]?.isConnected == true && !connectedIDs.contains(id) {
            devices[id]?.isConnected = false
        }
        for peripheral in connected {
            if var device = devices[peripheral.identifier] {
                device.isConnected = true
                device.name = device.name ?? peripheral.name
                devices[peripheral.identifier] = device
            } else {
                devices[peripheral.identifier] = BLEDevice(
                    id: peripheral.identifier,
                    name: peripheral.name,
                    rssi: nil,
                    isConnected: true,
                    lastSeen: now
                )
            }
        }
    }

    private func startPruning() {
        pruneTask?.cancel()
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                self.pruneStaleDevices()
            }
        }
    }

    private func pruneStaleDevices() {
        let cutoff = Date.now.addingTimeInterval(-Self.staleInterval)
        devices = devices.filter { $0.value.isConnected || $0.value.lastSeen >= cutoff }
        if let centralManager {
            refreshConnectedDevices(with: centralManager)
        }
    }

    private func handleStateUpdate(_ state: CBManagerState) {
        bluetoothState = state
        switch state {
        case .poweredOn:
            if scanRequested, let centralManager {
                isScanning = true
                beginScan(with: centralManager)
            }
        case .poweredOff, .unauthorized, .unsupported, .resetting:
            // The system stops scanning in these states; keep `scanRequested` so scanning resumes
            // automatically when Bluetooth is switched back on.
            isScanning = false
            pruneTask?.cancel()
            pruneTask = nil
        default:
            break
        }
    }

    private func handleDiscovery(id: UUID, name: String?, rssi: Int) {
        // 127 means the RSSI value is not available.
        guard rssi != 127 else { return }
        let now = Date.now

        if var device = devices[id] {
            let nameChanged = name != nil && name != device.name
            guard nameChanged || now.timeIntervalSince(device.lastSeen) >= Self.updateInterval else { return }
            if let name { device.name = name }
            device.rssi = rssi
            device.lastSeen = now
            devices[id] = device
        } else {
            devices[id] = BLEDevice(id: id, name: name, rssi: rssi, isConnected: false, lastSeen: now)
        }
    }
}

extension BluetoothViewModel: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated {
            handleStateUpdate(state)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            handleDiscovery(id: id, name: name, rssi: rssi)
        }
    }
}
