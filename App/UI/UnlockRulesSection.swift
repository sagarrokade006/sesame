import SesameCore
import SwiftUI

/// "Only unlock when…": trusted Wi-Fi, a connected Bluetooth device, and set hours.
struct UnlockRulesSection: View {
    let vault: Vault

    @State private var network: String?
    @State private var canReadNetwork = false
    @State private var devices: [UnlockRules.Device] = []

    private var surroundings: Surroundings { .shared }
    private var rules: UnlockRules { vault.contents.settings.unlockRules }

    private func change(_ edit: (inout UnlockRules) -> Void) {
        vault.update { edit(&$0.settings.unlockRules) }
    }

    private func refresh() {
        canReadNetwork = surroundings.canReadNetwork
        network = surroundings.network
        devices = surroundings.pairedDevices
    }

    var body: some View {
        SectionLabel(text: "Only unlock when")
        Panel {
            wifi
            PanelDivider()
            bluetooth
            PanelDivider()
            hours
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: Surroundings.accessChanged)) { _ in
            let wasAsking = !canReadNetwork
            refresh()
            // Finishes turning the rule on once Location access arrives.
            if wasAsking, canReadNetwork, rules.trustedNetworks.isEmpty, let network {
                change { $0.trustedNetworks = [network] }
            }
        }
    }

    // MARK: Wi-Fi

    private var wifiDetail: String {
        if !canReadNetwork { return "Needs Location access, which is how macOS shares the network name." }
        if let network { return rules.trustedNetworks.contains(network) ? "Connected to \(network)." : "Connected to \(network), which isn't trusted." }
        return "Not connected to Wi-Fi."
    }

    @ViewBuilder private var wifi: some View {
        PanelRow(title: "On trusted Wi-Fi", detail: rules.trustedNetworks.isEmpty ? "Any network." : wifiDetail) {
            Toggle("", isOn: Binding(
                get: { !rules.trustedNetworks.isEmpty },
                set: { on in
                    if on { trustCurrentNetwork() } else { change { $0.trustedNetworks = [] } }
                }
            ))
            .labelsHidden().toggleStyle(.switch).tint(Theme.mint)
            .disabled(rules.trustedNetworks.isEmpty && canReadNetwork && network == nil)
        }
        if !rules.trustedNetworks.isEmpty {
            ForEach(rules.trustedNetworks, id: \.self) { name in
                PanelRow(title: name) {
                    Button("Remove") { change { $0.trustedNetworks.removeAll { $0 == name } } }
                        .disabled(rules.trustedNetworks.count == 1)
                }
                .padding(.leading, 12)
            }
            if let network, canReadNetwork, !rules.trustedNetworks.contains(network) {
                PanelRow(title: "Trust \(network)") {
                    Button("Add") { change { $0.trustedNetworks.append(network) } }
                }
                .padding(.leading, 12)
            }
        }
    }

    private func trustCurrentNetwork() {
        guard canReadNetwork else {
            surroundings.requestNetworkAccess()
            return
        }
        refresh()
        guard let network else { return }
        change { $0.trustedNetworks = [network] }
    }

    // MARK: Bluetooth

    private var bluetooth: some View {
        PanelRow(title: "Near a Bluetooth device", detail: bluetoothDetail) {
            Picker("", selection: Binding(
                get: { rules.device?.address },
                set: { address in change { $0.device = devices.first { $0.address == address } } }
            )) {
                Text("Any time").tag(String?.none)
                if let saved = rules.device, !devices.contains(saved) {
                    Text(saved.name).tag(Optional(saved.address))
                }
                ForEach(devices) { Text($0.name).tag(Optional($0.address)) }
            }
            .labelsHidden()
            .frame(width: 160)
        }
    }

    private var bluetoothDetail: String {
        guard let device = rules.device else { return "Unlocks without one." }
        return surroundings.isConnected(device) ? "\(device.name) is connected." : "\(device.name) isn't connected right now."
    }

    // MARK: Hours

    @ViewBuilder private var hours: some View {
        PanelRow(title: "During set hours", detail: rules.hours == nil ? "Any time of day." : "Outside these hours, use your password.") {
            Toggle("", isOn: Binding(
                get: { rules.hours != nil },
                set: { on in change { $0.hours = on ? UnlockRules.Hours() : nil } }
            ))
            .labelsHidden().toggleStyle(.switch).tint(Theme.mint)
        }
        if let window = rules.hours {
            PanelRow(title: "From") {
                DatePicker("", selection: time(\.start, in: window), displayedComponents: .hourAndMinute).labelsHidden()
            }
            .padding(.leading, 12)
            PanelRow(title: "Until", detail: window.start > window.end ? "Runs overnight." : nil) {
                DatePicker("", selection: time(\.end, in: window), displayedComponents: .hourAndMinute).labelsHidden()
            }
            .padding(.leading, 12)
            PanelRow(title: "Weekdays only") {
                Toggle("", isOn: Binding(
                    get: { window.weekdaysOnly },
                    set: { only in change { $0.hours?.weekdaysOnly = only } }
                ))
                .labelsHidden().toggleStyle(.switch).tint(Theme.mint)
            }
            .padding(.leading, 12)
        }
    }

    /// Shows minutes after midnight as a time today.
    private func time(_ path: WritableKeyPath<UnlockRules.Hours, Int>, in window: UnlockRules.Hours) -> Binding<Date> {
        let midnight = Calendar.current.startOfDay(for: Date())
        return Binding(
            get: { midnight.addingTimeInterval(TimeInterval(window[keyPath: path] * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                change { $0.hours?[keyPath: path] = minutes }
            }
        )
    }
}
