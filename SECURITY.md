# Security

- Keep OBS WebSocket authenticated and local to the server. The bridge connects only to loopback.
- SSH authenticates the controller. Use trusted keys and verify fingerprints. No new HTTP listener.
- NDI is a separate video transport on your trusted LAN; do not expose it or OBS to the internet.
- Private server config lives outside the checkout with mode 600. Never commit it or RTMP keys.
- Live start requires explicit confirmation. Test automation must never call real public starts.
- The controller checks profile/collection before edits. Unknown commands are rejected.
- Camera/microphone setup is manual. No browser scraping, no silent device acquisition on launch.
- Closing the client leaves OBS running. It stops this client's screen capture: plan that transition.
- File copy preserves originals. Do not put sensitive files into a recording directory you share.

Report security issues privately through GitHub security advisories, not with credentials in an issue.
