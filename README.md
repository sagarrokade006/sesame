# Sesame

Face unlock for your Mac. Sesame recognizes you when your Mac wakes and signs you in, entirely on-device.

![Sesame](docs/overview.png)

> [!WARNING]
> Sesame is a convenience tool and isn't as secure as Face ID or Touch ID. A Mac webcam sees a flat image, and macOS
> has no way for an app to approve a login, so Sesame types your saved password at the lock screen.

## Requirements

- macOS 15 or later
- A camera, and Touch ID or a Mac password
- Xcode 26 or later to build

## Build

1. Open `Sesame.xcodeproj`.
2. Choose your team under Signing & Capabilities for the `Sesame` target.
3. Run.

## How it protects you

- Touch ID or your Mac password is needed after every restart and every 48 hours by default.
- Face unlock pauses after 5 failed attempts until the Mac is unlocked another way.
- Adding a face, changing the saved password, and changing security settings need fresh authentication.
- Faces, password, history, and settings are stored in one AES-GCM encrypted file.
- Only real cameras are used. Virtual cameras are ignored.

## Tests

```bash
cd Packages/SesameCore && swift test
```

## Third-party

The face recognition model is [SFace](https://huggingface.co/opencv/face_recognition_sface) from OpenCV, under the
Apache License 2.0. Its license is in `App/Models/SFace-LICENSE.txt`, and `tools/convert_model.py` converts it for Core ML.

The lock-screen badge uses private macOS window server APIs, which may change in any macOS update.
