import SesameCore
import SwiftUI

/// Where and when face unlock may run: trusted Wi-Fi, a connected Bluetooth device, and set hours.
struct ConditionsPage: View {
    let model: AppModel

    @State private var network: String?
    @State private var canReadNetwork = false
    /// Stays nil until Bluetooth is needed, because listing devices asks macOS for Bluetooth access.
    @State private var devices: [UnlockRules.Device]?

    private var vault: Vault { model.vault }
    private var surroundings: Surroundings { .shared }
    private var rules: UnlockRules { vault.contents.settings.unlockRules }

    private func change(_ edit: (inout UnlockRules) -> Void) {
        vault.update { edit(&$0.settings.unlockRules) }
    }

    private func refresh() {
        canReadNetwork = surroundings.canReadNetwork
        network = canReadNetwork ? surroundings.network : nil
        if rules.device != nil || devices != nil { devices = surroundings.pairedDevices }
    }

    var body: some View {
        statusBanner

        ApprovalGate(vault: vault, reason: "change when Sesame can unlock") {
            wifiCard
            bluetoothCard
            hoursCard
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

    @ViewBuilder private var statusBanner: some View {
        if rules.isEmpty {
            Banner(symbol: "globe", tint: Theme.sky, title: "Face unlock works anywhere, any time",
                   detail: "Turn on a condition below to limit it. When one isn't met, use your password as usual.")
        } else if let unmet = surroundings.firstUnmet(rules) {
            Banner(symbol: "pause.circle.fill", tint: Theme.amber, title: "Face unlock is off right now", detail: unmet.explanation)
        } else {
            Banner(symbol: "checkmark.circle.fill", tint: Theme.mint, title: "All conditions are met", detail: "Face unlock is allowed right now.")
        }
    }

    // MARK: Wi-Fi

    private var wifiCard: some View {
        Card {
            SettingRow(icon: "wifi", tint: Theme.sky, title: "Trusted Wi-Fi", detail: wifiDetail) {
                Switch(isOn: Binding(
                    get: { !rules.trustedNetworks.isEmpty },
                    set: { on in if on { trustCurrentNetwork() } else { change { $0.trustedNetworks = [] } } }
                ))
                .disabled(rules.trustedNetworks.isEmpty && canReadNetwork && network == nil)
            }
            if !rules.trustedNetworks.isEmpty {
                ForEach(rules.trustedNetworks, id: \.self) { name in
                    RowDivider()
                    HStack(spacing: 10) {
                        Image(systemName: name == network ? "wifi" : "wifi.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(name == network ? Theme.mint : Theme.tertiary)
                            .frame(width: 16)
                        Text(name).font(.system(size: 13)).foregroundStyle(Theme.primary)
                        if name == network {
                            Text("Connected")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Theme.mint)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Theme.mint.opacity(0.14), in: Capsule())
                        }
                        Spacer()
                        Button { change { $0.trustedNetworks.removeAll { $0 == name } } } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 15))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.tertiary)
                        .help(rules.trustedNetworks.count == 1 ? "Turn off Trusted Wi-Fi to remove the last network" : "Stop trusting \(name)")
                        .disabled(rules.trustedNetworks.count == 1)
                    }
                    .padding(.leading, 58)
                    .padding(.trailing, 16)
                    .frame(height: 40)
                }
                if let network, canReadNetwork, !rules.trustedNetworks.contains(network) {
                    RowDivider()
                    Button { change { $0.trustedNetworks.append(network) } } label: {
                        Label("Trust \(network)", systemImage: "plus.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.mint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 58)
                    .frame(height: 40)
                }
            }
        }
    }

    private var wifiDetail: String {
        if !canReadNetwork { return "Needs Location access, which is how macOS shares the network name. Nothing else is read." }
        if rules.trustedNetworks.isEmpty {
            return network.map { "Only unlock on networks you choose. You're on \($0)." } ?? "Connect to Wi-Fi to choose a trusted network."
        }
        guard let network else { return "Not connected to Wi-Fi, so face unlock is off." }
        return rules.trustedNetworks.contains(network) ? "You're on a trusted network." : "\(network) isn't trusted, so face unlock is off."
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

    private var bluetoothCard: some View {
        Card {
            SettingRow(icon: "applewatch", tint: Theme.violet, title: "Nearby device", detail: bluetoothDetail) {
                Switch(isOn: Binding(
                    get: { rules.device != nil || devices != nil },
                    set: { on in
                        if on {
                            devices = surroundings.pairedDevices
                        } else {
                            devices = nil
                            change { $0.device = nil }
                        }
                    }
                ))
            }
            if let devices {
                RowDivider()
                HStack {
                    Text("Device").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { rules.device?.address },
                        set: { address in change { $0.device = devices.first { $0.address == address } } }
                    )) {
                        Text("Choose…").tag(String?.none)
                        if let saved = rules.device, !devices.contains(saved) {
                            Text(saved.name).tag(Optional(saved.address))
                        }
                        ForEach(devices) { Text($0.name).tag(Optional($0.address)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.leading, 58)
                .padding(.trailing, 16)
                .frame(height: 44)
            }
        }
    }

    private var bluetoothDetail: String {
        guard let device = rules.device else {
            return devices == nil ? "Only unlock while a paired device, like your watch, is connected." : "Choose one of your paired Bluetooth devices."
        }
        return surroundings.isConnected(device) ? "\(device.name) is connected." : "\(device.name) isn't connected, so face unlock is off."
    }

    // MARK: Hours

    private var hoursCard: some View {
        Card {
            SettingRow(icon: "clock.fill", tint: Theme.amber, title: "Set hours", detail: hoursDetail) {
                Switch(isOn: Binding(
                    get: { rules.hours != nil },
                    set: { on in change { $0.hours = on ? UnlockRules.Hours() : nil } }
                ))
            }
            if let window = rules.hours {
                RowDivider()
                HStack(spacing: 8) {
                    Text("From").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    DatePicker("", selection: time(\.start, in: window), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                    Text("to").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    DatePicker("", selection: time(\.end, in: window), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                    Spacer()
                }
                .padding(.leading, 58)
                .padding(.trailing, 16)
                .frame(height: 44)
                RowDivider()
                HStack {
                    Text("Weekdays only").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Switch(isOn: Binding(
                        get: { window.weekdaysOnly },
                        set: { only in change { $0.hours?.weekdaysOnly = only } }
                    ))
                }
                .padding(.leading, 58)
                .padding(.trailing, 16)
                .frame(height: 44)
            }
        }
    }

    private var hoursDetail: String {
        guard let window = rules.hours else { return "Only unlock during part of the day, like work hours." }
        let days = window.weekdaysOnly ? "on weekdays" : "every day"
        let overnight = window.start > window.end ? ", overnight" : ""
        return "\(clock(window.start)) to \(clock(window.end)) \(days)\(overnight)."
    }

    private func clock(_ minutes: Int) -> String {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes * 60))
            .formatted(date: .omitted, time: .shortened)
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
