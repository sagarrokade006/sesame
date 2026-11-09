import Testing
@testable import SesameCore

@Suite struct PermissionGateTests {
    @Test func grantedAtLaunchIsReady() {
        var gate = PermissionGate(grantedAtLaunch: true)
        #expect(gate.state == .ready)
        #expect(gate.observe(granted: true) == .ready)
    }

    @Test func deniedAtLaunchAsksFirst() {
        var gate = PermissionGate(grantedAtLaunch: false)
        #expect(gate.state == .needsPermission)
        #expect(gate.observe(granted: false) == .needsPermission)
    }

    /// The case that left the button stuck on Allow: macOS kept saying no to the running copy after it was granted.
    @Test func afterAskingARestartIsOfferedEvenIfMacOSStillSaysNo() {
        var gate = PermissionGate(grantedAtLaunch: false)
        gate.noteAsked(grantedNow: false)
        #expect(gate.state == .needsRestart)
        #expect(gate.observe(granted: false) == .needsRestart)
    }

    @Test func grantedWhileRunningStillNeedsARestart() {
        var gate = PermissionGate(grantedAtLaunch: false)
        #expect(gate.observe(granted: true) == .needsRestart)
    }

    @Test func revokedAndRegrantedWhileRunningNeedsARestart() {
        var gate = PermissionGate(grantedAtLaunch: true)
        gate.observe(granted: false)
        #expect(gate.state == .needsPermission)
        #expect(gate.observe(granted: true) == .needsRestart)
    }

    @Test func blockedKeystrokesNeedARestartEvenWhenGranted() {
        var gate = PermissionGate(grantedAtLaunch: true)
        gate.noteBlocked()
        #expect(gate.state == .needsRestart)
        #expect(gate.observe(granted: true) == .needsRestart)
    }

    @Test func entryMissFollowsTheRecheck() {
        #expect(EntryMiss(recheck: .accepted) == .keystrokesBlocked)
        #expect(EntryMiss(recheck: .rejected) == .wrongPassword)
        #expect(EntryMiss(recheck: .unavailable) == .unknown)
    }
}
