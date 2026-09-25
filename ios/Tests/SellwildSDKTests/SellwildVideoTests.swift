import XCTest
@testable import SellwildSDK

/// Unit tests for `SellwildVideo` remote-config gating — the decisions of
/// WHETHER outstream video is enabled and WHETHER its audio plays, independent
/// of the Prebid fork rendering (which is exercised by the build/sim gate).
final class SellwildVideoTests: XCTestCase {

    // MARK: soundEnabled (drives the enforced player mute)

    func testSoundDefaultsToMutedWhenUnset() throws {
        // No remote config → muted (soundEnabled == false).
        XCTAssertFalse(SellwildVideo.soundEnabled(remoteValues: nil, zoneId: "43"))
        XCTAssertFalse(SellwildVideo.soundEnabled(remoteValues: try AppConfigFactory.remote(["CODE": "weatherbug"]), zoneId: "43"))
    }

    func testGlobalSoundFlagForcesSoundOn() throws {
        XCTAssertTrue(SellwildVideo.soundEnabled(remoteValues: try AppConfigFactory.remote(["VIDEO_SOUND_ENABLED": true]), zoneId: "43"))
        XCTAssertTrue(SellwildVideo.soundEnabled(remoteValues: try AppConfigFactory.remote(["VIDEO_SOUND_ENABLED": "1"]), zoneId: "43"))
        XCTAssertTrue(SellwildVideo.soundEnabled(remoteValues: try AppConfigFactory.remote(["VIDEO_SOUND_ENABLED": "true"]), zoneId: nil))
    }

    func testPerZoneSoundFlagIsScopedToZone() throws {
        let remote = try AppConfigFactory.remote(["VIDEO_SOUND_ENABLED_BY_ZONE": ["43": true]])
        XCTAssertTrue(SellwildVideo.soundEnabled(remoteValues: remote, zoneId: "43"))
        // A different zone is unaffected → stays muted.
        XCTAssertFalse(SellwildVideo.soundEnabled(remoteValues: remote, zoneId: "99"))
        // No zone context → cannot match the per-zone map → muted.
        XCTAssertFalse(SellwildVideo.soundEnabled(remoteValues: remote, zoneId: nil))
    }

    func testFalsyGlobalFallsThroughToPerZone() throws {
        // A CMS-emitted VIDEO_SOUND_ENABLED:false must not dead-letter the
        // per-zone map (same gotcha guarded in isEnabled / AD_STACK_BY_ZONE).
        let remote = try AppConfigFactory.remote([
            "VIDEO_SOUND_ENABLED": false,
            "VIDEO_SOUND_ENABLED_BY_ZONE": ["43": true],
        ])
        XCTAssertTrue(SellwildVideo.soundEnabled(remoteValues: remote, zoneId: "43"))
        XCTAssertFalse(SellwildVideo.soundEnabled(remoteValues: remote, zoneId: "99"))
    }

    // MARK: isEnabled (gates whether the mute path even runs)

    func testVideoDefaultsToDisabled() throws {
        XCTAssertFalse(SellwildVideo.isEnabled(remoteValues: nil, zoneId: "43"))
        XCTAssertFalse(SellwildVideo.isEnabled(remoteValues: try AppConfigFactory.remote(["CODE": "weatherbug"]), zoneId: "43"))
    }

    func testGlobalVideoFlagAndPerZoneMap() throws {
        XCTAssertTrue(SellwildVideo.isEnabled(remoteValues: try AppConfigFactory.remote(["VIDEO_ENABLED": true]), zoneId: "43"))
        let remote = try AppConfigFactory.remote(["VIDEO_ENABLED_BY_ZONE": ["43": true]])
        XCTAssertTrue(SellwildVideo.isEnabled(remoteValues: remote, zoneId: "43"))
        XCTAssertFalse(SellwildVideo.isEnabled(remoteValues: remote, zoneId: "99"))
    }
}
