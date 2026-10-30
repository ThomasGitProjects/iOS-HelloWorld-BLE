import SwiftUI
import UIKit

struct ContentView: View {
    @State private var viewModel = BluetoothViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                if let message = viewModel.stateMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        if viewModel.needsSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                            Button("Einstellungen öffnen") { openURL(url) }
                        }
                    }
                }

                if !viewModel.devices.isEmpty {
                    Section("\(viewModel.devices.count) Geräte") {
                        ForEach(viewModel.sortedDevices) { device in
                            DeviceRow(device: device)
                        }
                    }
                }
            }
            .overlay {
                if viewModel.devices.isEmpty && viewModel.stateMessage == nil {
                    emptyState
                }
            }
            .animation(.default, value: viewModel.sortedDevices.map(\.id))
            .navigationTitle("BLE Scanner")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isScanning {
                        ProgressView()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                scanButton
            }
        }
    }

    private var scanButton: some View {
        Button {
            viewModel.toggleScan()
        } label: {
            Label(
                viewModel.isScanning ? "Scan stoppen" : "Scan starten",
                systemImage: viewModel.isScanning ? "stop.fill" : "antenna.radiowaves.left.and.right"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isScanning ? .red : .accentColor)
        .padding()
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isScanning {
            ContentUnavailableView {
                Label("Suche nach Geräten …", systemImage: "dot.radiowaves.left.and.right")
            } description: {
                Text("BLE-Geräte in der Nähe erscheinen hier automatisch.")
            }
        } else {
            ContentUnavailableView {
                Label("Keine Geräte", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text("Tippe auf „Scan starten“, um nach Bluetooth-Geräten zu suchen.")
            }
        }
    }
}

private struct DeviceRow: View {
    let device: BLEDevice

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.headline)
                    if device.isConnected {
                        Text("Verbunden")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(device.id.uuidString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "cellularbars", variableValue: device.signalQuality)
                    .foregroundStyle(device.rssi == nil ? .secondary : .primary)
                Text(device.rssi.map { "\($0) dBm" } ?? "– dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView()
}
