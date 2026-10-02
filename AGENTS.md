# Anima Studio public edition

This is a standalone public export, not the author's installed private Studio.
Never modify private OBS profiles, apps, credentials or production services when testing.
Test with mocks or explicitly isolated camera-free resources. Never start a public stream in QA.
Do not auto-acquire a camera or auto-start NDI on launch. User must select a monitor.
Run `npm test` and `swift test`. Changes must preserve server/client separation and SSH quoting.
No secrets, personal infrastructure routes or third-party binaries belong in this repository.
