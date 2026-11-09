import AppKit
import IOKit.hid

/// Lets someone ask for another scan at the lock screen, by pressing Space or moving the pointer to the top of the screen.
/// Runs only while the Mac is locked.
@MainActor
final class RetryTriggers {
    /// Holds what the C callback needs. Only ever used to hop back to the main actor.
    private final class SpaceHandler: @unchecked Sendable {
        let action: @Sendable () -> Void
        init(_ action: @escaping @Sendable () -> Void) { self.action = action }
    }

    var onRequest: (() -> Void)?
    /// The area of the screen that counts as "at the notch".
    var hotZone: (() -> CGRect?)?

    private var pointerTimer: Timer?
    private var wasInHotZone = false
    private var manager: IOHIDManager?
    private var spaceHandler: SpaceHandler?

    func start() {
        guard pointerTimer == nil else { return }
        wasInHotZone = hotZone?()?.contains(NSEvent.mouseLocation) ?? false
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        startListeningForSpace()
    }

    func stop() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        spaceHandler = nil
    }

    /// Fires on arrival only, so resting the pointer there doesn't keep rescanning.
    private func checkPointer() {
        let isInside = hotZone?()?.contains(NSEvent.mouseLocation) ?? false
        if isInside, !wasInHotZone { onRequest?() }
        wasInHotZone = isInside
    }

    /// The login window blocks ordinary key monitoring, so this reads the keyboard device and looks only at the
    /// Space bar. If macOS hasn't granted access, the pointer still works.
    private func startListeningForSpace() {
        guard manager == nil, IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else { return }

        let device = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(device, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)

        let handler = SpaceHandler { [weak self] in
            Task { @MainActor in self?.onRequest?() }
        }
        spaceHandler = handler
        IOHIDManagerRegisterInputValueCallback(device, { context, _, _, value in
            let element = IOHIDValueGetElement(value)
            guard let context,
                  IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
                  IOHIDElementGetUsage(element) == UInt32(kHIDUsage_KeyboardSpacebar),
                  IOHIDValueGetIntegerValue(value) == 1
            else { return }
            Unmanaged<SpaceHandler>.fromOpaque(context).takeUnretainedValue().action()
        }, Unmanaged.passUnretained(handler).toOpaque())

        IOHIDManagerScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            spaceHandler = nil
            return
        }
        manager = device
    }
}
