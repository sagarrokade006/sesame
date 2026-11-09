# Changelog

Every release of Sesame, newest first. The app shows the latest entry after it updates, and the update window shows it
before you install.

## 1.0.3

- Sesame can open when you log in, and asks for Touch ID as soon as it starts, so a restart no longer leaves face
  unlock off. Turn it on from Overview or About.
- Pause face unlock from the menu bar or Overview: for 1 hour, until tomorrow, or until you turn it back on.
- Test face unlock on the Faces page: see how well you match and whether Sesame saw you blink, without locking your
  Mac.
- Sesame tells you when it's too dark to see you, instead of failing without a reason.
- Rename a face, and see how often and when each one was last used.
- Get a notification after unlocking if someone else tried while you were away, and optionally a sound when face
  unlock signs you in. Both are in Security.
- Filter Activity by unlocks or failed attempts.
- A scan can no longer get stuck: if the camera is busy, unplugged, or stops responding, Sesame tries once more and
  then tells you, instead of blocking later scans.
- Scanning stops when the display sleeps or the lid closes, and the camera recovers on its own after an error.
- Your saved data now keeps a last good copy and falls back to it if the file is damaged, and Sesame tells you if a
  save fails.
- New menu bar panel with status and last unlock, a week chart on Overview, and smoother navigation.
- The Touch ID interval can't be stretched by changing the Mac's clock, and changing it in Security applies right away.

## 1.0.2

- Sesame now tries again on its own: up to three more times when it sees you but you haven't blinked yet, and once
  when it didn't see anyone.
- Moving the pointer or trackpad anywhere on screen starts another scan, not just at the notch.
- Removed Space as a way to scan again, along with its Input Monitoring permission. At the lock screen macOS hides key
  presses from every app, so it could never work.
- New in Security: Require a blink, for when only a blink should prove you're there.

## 1.0.1

- Face unlock now needs a clear view of your face. A partly covered face, or a photo held over someone else's face,
  can no longer unlock your Mac, even if it blinks.
- Adding a face now happens in the notch, right under the camera, and stays visible even when Sesame's window is behind
  other apps.
- Sesame comes back to the front after you approve Touch ID, the camera, or Accessibility, instead of staying hidden.
- See what's new after each update, on Overview and in About, and in the update window before installing.
- The daily update check now always notifies you when there's a new version.

## 1.0.0

- First public release.
- Face unlock that types your Mac password at the lock screen, with a blink or head movement as proof of life.
- Conditions: only unlock on trusted Wi-Fi, near a Bluetooth device, or during set hours.
- Updates from inside the app, with your faces, password, and permissions kept.
