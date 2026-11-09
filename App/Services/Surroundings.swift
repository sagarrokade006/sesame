import CoreLocation
import CoreWLAN
import Foundation
import IOBluetooth
import SesameCore

/// Reads the Wi-Fi network and Bluetooth devices that unlock rules depend on. macOS only names the Wi-Fi network for
/// apps with Location access, so nothing here asks for permission until a rule needs it.
@MainActor
final class Surroundings: NSObject, CLLocationManagerDelegate {
    static let shared = Surroundings()
    static let accessChanged = Notification.Name("SesameSurroundingsAccessChanged")

    private let location = CLLocationManager()

    override private init() {
        super.init()
        location.delegate = self
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in NotificationCenter.default.post(name: Self.accessChanged, object: nil) }
    }

    var canReadNetwork: Bool {
        let status = location.authorizationStatus
        return status == .authorizedAlways || status == .authorized
    }

    func requestNetworkAccess() {
        location.requestWhenInUseAuthorization()
    }

    var network: String? { CWWiFiClient.shared().interface()?.ssid() }

    var pairedDevices: [UnlockRules.Device] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap { device in
            guard let address = device.addressString else { return nil }
            return UnlockRules.Device(name: device.name ?? address, address: address)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func isConnected(_ device: UnlockRules.Device) -> Bool {
        IOBluetoothDevice(addressString: device.address)?.isConnected() ?? false
    }

    /// Only looks up what the rules actually use.
    func firstUnmet(_ rules: UnlockRules) -> UnlockRules.Unmet? {
        rules.firstUnmet(
            at: Date(),
            calendar: .current,
            network: rules.trustedNetworks.isEmpty ? nil : network,
            deviceConnected: rules.device.map(isConnected) ?? false
        )
    }
}
