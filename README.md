# Sesame

Face unlock for your Mac. Sesame recognizes you when your Mac wakes and signs you in, entirely on-device.

![Sesame](docs/overview.png)

> [!WARNING]
> Sesame is a convenience tool and isn't as secure as Face ID or Touch ID. A Mac webcam sees a flat image, and macOS
> has no way for an app to approve a login, so Sesame types your saved password at the lock screen.

## Install

1. Download the latest `Sesame-x.y.z.dmg` from [Releases](https://github.com/sagarrokade006/sesame/releases/latest),
   open it, and drag Sesame to Applications.
2. Open Sesame. Because it isn't notarized by Apple, macOS stops it the first time. Open **System Settings → Privacy &
   Security**, scroll down, and click **Open Anyway** next to the message about Sesame. You only do this once.
3. Follow the checklist on Overview: allow the camera and Accessibility, scan your face, and save your Mac password.

Sesame lives in the menu bar. Lock your Mac and look at the camera; blink if the notch asks you to.

## Updates

Sesame checks for a new version once a day. When one is out you'll get a notification, a banner on Overview, and a dot
next to About. Click **Update** to see what's new and install it; Sesame restarts on the new version.

![An update waiting on Overview](docs/update.png)

Your faces, password, settings, and macOS permissions carry over, because every release is signed with the same
certificate. Every update is also checked against Sesame's own update key before it's installed, so only releases
from this repository can replace it.

## A tour

| | |
|---|---|
| ![First run](docs/setup.png) | ![Faces](docs/faces.png) |
| **Setup.** A checklist for permissions, your face, and your password. | **Faces.** Add a face for glasses or a hat, and switch faces on and off. |
| ![Password](docs/password.png) | ![Security](docs/security.png) |
| **Password.** Saved encrypted, checked with macOS, typed only at the lock screen. | **Security.** Head-turn challenge, attention, Touch ID interval, match strictness. |
| ![Conditions](docs/conditions.png) | ![Activity](docs/activity.png) |
| **Conditions.** Only unlock on trusted Wi-Fi, near your watch, or during set hours. | **Activity.** Every unlock and failed attempt. No images are kept. |
| ![Help](docs/help.png) | ![About](docs/about.png) |
| **Help.** Searchable answers to common problems. | **About.** Version and updates. |

At the lock screen, Sesame shows its progress in the notch:

| Scanning | Turn your head | Unlocked | Not recognized |
|---|---|---|---|
| ![Scanning](docs/notch-scanning.png) | ![Turn](docs/notch-turn.png) | ![Success](docs/notch-success.png) | ![Failure](docs/notch-failure.png) |

## How it protects you

- Touch ID or your Mac password is needed after every restart and every 48 hours by default.
- Recognition needs several matching frames in a row, plus proof of life: a blink or a natural head movement. A face
  surrounded by a phone or picture frame is rejected.
- Face unlock pauses after 5 failed attempts until the Mac is unlocked another way.
- Adding a face, changing the saved password, and changing security settings need fresh authentication.
- Optional conditions limit unlocking to trusted Wi-Fi, a connected Bluetooth device, or set hours.
- Faces, password, history, and settings are stored in one AES-GCM encrypted file.
- Only real cameras are used. Virtual cameras are ignored.

## Requirements

- macOS 15 or later
- A camera, and Touch ID or a Mac password
- Xcode 26 or later to build

## Build

1. Open `Sesame.xcodeproj`.
2. Choose your team under Signing & Capabilities for the `Sesame` target.
3. Run.

Debug builds never update themselves. To render every screen with sample data, without Touch ID or permissions:

```bash
SESAME_SNAPSHOT_DIR=~/Desktop/sesame-shots path/to/Debug/Sesame.app/Contents/MacOS/Sesame
```

Add `SESAME_SNAPSHOT_SCENARIO=new`, `locked`, `restart`, or `update` for other states. That's how the screenshots here
are made.

## Tests

```bash
cd Packages/SesameCore && swift test
```

`tools/test_update.sh` proves updating works end to end without publishing anything: it builds an old and a new copy
under a test bundle ID, serves the new one from localhost with a throwaway key, and checks that the old copy finds it,
notifies, downloads, verifies, and installs it.

## Releasing

Every push to `main` that changes the app publishes a release on its own. GitHub Actions runs the tests, builds and
signs the DMG, signs the update, and publishes the DMG with the update feed (`appcast.xml`) that installed copies read.

The version is `MARKETING_VERSION` from the Xcode project (such as `1.0`) plus the number of commits, so releases go
`1.0.41`, `1.0.42`, and so on, always newer than the last. Change `MARKETING_VERSION` for a bigger step. Pushes that
only touch the README or docs don't release. To release by hand, or to test the pipeline without publishing, run the
**Release** workflow from the Actions tab and switch off **Publish**.

### One-time setup

Sesame is open source and released without an Apple Developer account, so two keys stand in for one. Run both from
the repo root; each stores its secret in your login Keychain and in this repository's Actions secrets, and refuses to
replace an existing one.

1. `swift tools/setup_update_key.swift` creates the update key and writes its public half to `Config/Info.plist`.
   Commit that change. Without the private half, no one can publish an update that installed copies will accept.
2. `tools/setup_signing_certificate.sh` creates the self-signed certificate every release is signed with. macOS
   remembers Camera, Accessibility, and Input Monitoring, and the Keychain keeps Sesame's key, only while the signature
   stays the same from version to version. Without it, every update would ask for all permissions again.

Keep the Keychain backups. A lost update key means installed copies can't update; a lost certificate means everyone
grants permissions once more.

If you later get a Developer ID, `tools/build_release.sh` also supports `DEVELOPER_ID_IDENTITY` and notarization, which
removes the **Open Anyway** step.

## Third-party

The face recognition model is [SFace](https://huggingface.co/opencv/face_recognition_sface) from OpenCV, under the
Apache License 2.0. Its license is in `App/Models/SFace-LICENSE.txt`, and `tools/convert_model.py` converts it for Core ML.

The lock-screen animation uses private macOS window server APIs, which may change in any macOS update.

Updates use [Sparkle](https://sparkle-project.org). Sesame is released under the [MIT License](LICENSE).
