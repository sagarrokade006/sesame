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

Sesame lives in the menu bar. When your Mac wakes, look at the camera and blink if the notch asks you to. If a scan
doesn't work out, Sesame tries again on its own, and moving the pointer or trackpad anywhere starts another scan. You
can always type your password as usual.

## Updates

Sesame checks for a new version once a day. When one is out you'll get a notification, a banner on Overview, and a dot
next to About. Click **Update** to see what's new and install it; Sesame restarts on the new version.

![An update waiting on Overview](docs/update.png)

After it updates, Sesame tells you what changed, on Overview and in About. Every release's notes are in
[CHANGELOG.md](App/Resources/CHANGELOG.md).

![What's new after an update](docs/updated.png)

Your faces, password, settings, and macOS permissions carry over, because every release is signed by the same Apple
team. Every update is also checked against Sesame's own update key before it's installed, so only releases
from this repository can replace it.

## A tour

| | |
|---|---|
| ![First run](docs/setup.png) | ![Faces](docs/faces.png) |
| **Setup.** A checklist for permissions, your face, and your password. | **Faces.** Add a face for glasses or a hat, and switch faces on and off. |
| ![Password](docs/password.png) | ![Security](docs/security.png) |
| **Password.** Saved encrypted, checked with macOS, typed only at the lock screen. | **Security.** Head-turn challenge, attention, blink only, Touch ID interval, match strictness. |
| ![Conditions](docs/conditions.png) | ![Activity](docs/activity.png) |
| **Conditions.** Only unlock on trusted Wi-Fi, near your watch, or during set hours. | **Activity.** Every unlock and failed attempt. No images are kept. |
| ![Help](docs/help.png) | ![About](docs/about.png) |
| **Help.** Searchable answers to common problems. | **About.** Version, what's new, and updates. |

Adding a face happens in the notch, right under the camera you're looking at:

<p align="center"><img src="docs/notch-scan.png" width="320" alt="Scanning a face in the notch"></p>

At the lock screen, Sesame shows its progress in the notch too:

| Scanning | Blink to unlock | Turn your head |
|---|---|---|
| ![Scanning](docs/notch-scanning.png) | ![Blink to unlock](docs/notch-blink.png) | ![Turn your head](docs/notch-turn.png) |
| **Unlocked** | **Not recognized** | **Try again** |
| ![Unlocked](docs/notch-success.png) | ![Not recognized](docs/notch-failure.png) | ![Try again](docs/notch-retry.png) |

When Sesame recognizes you but hasn't seen you blink or move yet, it asks you to blink. A scan that sees you tries up
to three more times on its own, and one that sees nobody tries once more. After that, move the pointer or trackpad to
scan again. The keyboard can't start a scan: at the lock screen macOS hides key presses from every app, to protect your
password.

## How it protects you

- Touch ID or your Mac password is needed after every restart and every 48 hours by default.
- Recognition needs several clear matches in a row, plus proof of life: a blink or a natural head movement, seen on a
  face that clearly matches. A partly covered face, or a photo held over someone else's face, can't unlock or vouch for
  a blink. A face surrounded by a phone or picture frame is rejected. Turn on **Require a blink** in Security to accept
  only a blink.
- Face unlock pauses after 5 failed attempts until the Mac is unlocked another way. A suspected spoof never retries on
  its own.
- Sesame doesn't scan the moment your Mac locks, and ignores the pointer for 3 seconds after, so locking and walking
  away doesn't unlock it again.
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

Add `SESAME_SNAPSHOT_SCENARIO=new`, `locked`, `keymissing`, `restart`, `update`, or `updated` for other states, and
`SESAME_SNAPSHOT_PAGES=notch,badges` for the notch face scan and the lock-screen badges. That's how every screenshot
here is made.

## Tests

```bash
cd Packages/SesameCore && swift test
```

`tools/test_update.sh` proves updating works end to end without publishing anything: it builds an old and a new copy
under a test bundle ID, serves the new one from localhost with a throwaway key, and checks that the old copy finds it,
notifies, downloads, verifies, and installs it.

## Releasing

Releases are numbered `1.0.0`, `1.0.1`, `1.0.2`, and so on: each takes the next patch number in the series set by
`MARKETING_VERSION` in the Xcode project. Set it to `1.1.0` to start the next series. The build number is the commit
count, which is what installed copies compare to decide that a release is newer.

Before releasing, add a `## <version>` section to [CHANGELOG.md](App/Resources/CHANGELOG.md). Both release paths refuse
to publish without one. Its bullets become the GitHub release notes, the update window's notes, and the app's What's
New.

### From your Mac

```bash
tools/release_local.sh
```

Run it on `main` with everything pushed. It tests, builds, signs, signs the update, writes the update feed
(`appcast.xml`), and publishes the DMG and feed to GitHub Releases.

### From GitHub Actions

The workflows are turned off; turn **Release** back on in the Actions tab to use it. Then every push to `main` that
changes the app runs the same steps on GitHub. Pushes that only touch the README or docs
don't release. Run the **Release** workflow from the Actions tab by hand and switch off **Publish** to test the
pipeline without releasing.

### Signing, without a paid developer account

Releases are signed with the free **Apple Development** certificate Xcode creates for your Apple ID (Xcode › Settings
› Accounts). Because Apple issued it, macOS recognizes every release as the same app, so Camera,
Accessibility, and the Keychain item holding Sesame's key all carry over between updates. Builds from Xcode use
the same certificate and store their key in the same place, so you can switch between a build from Xcode and a
release without losing your data. Both release paths refuse to publish a build signed any other way.

Without notarization, which needs a paid account, macOS asks people to click **Open Anyway** the first time they open
Sesame. Updates install without that step.

### One-time setup

1. `swift tools/setup_update_key.swift` creates the update key, stores the private half in your login Keychain and
   the repo's Actions secrets, and writes the public half to `Config/Info.plist`. Commit that change. Installed copies
   only accept updates signed with this key, so keep the Keychain backup.
2. For GitHub Actions only: export your Apple Development certificate from Keychain Access as a `.p12`, then run
   `tools/setup_ci_signing.sh path/to/certificate.p12`.

If you later get a Developer ID, `tools/build_release.sh` also supports `DEVELOPER_ID_IDENTITY` and notarization, which
removes the **Open Anyway** step.

## Third-party

The face recognition model is [SFace](https://huggingface.co/opencv/face_recognition_sface) from OpenCV, under the
Apache License 2.0. Its license is in `App/Models/SFace-LICENSE.txt`, and `tools/convert_model.py` converts it for Core ML.

The lock-screen animation uses private macOS window server APIs, which may change in any macOS update.

Updates use [Sparkle](https://sparkle-project.org). Sesame is released under the [MIT License](LICENSE).
