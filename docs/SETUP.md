# Two-Mac setup

The client is a controller AND a screen sender. The server performs composition,
encoding, recording and platform delivery. SSH carries commands/previews; NDI carries
screen video on your trusted local network. SSH alone does not transport NDI.

## 1. Server: prepare OBS once

- Use a dedicated profile and scene collection called `Anima`, or map your existing names.
- Keep the Mac awake and logged into its graphical session. OBS is a desktop app, not a headless daemon.
- Create scenes `Talk`, `Screen`, `Pause`. Add your camera to Talk, your content to Screen,
  and a break card to Pause. Name the microphone `Mic`; route it to the recording/stream audio tracks.
- Choose an OBS recording directory; create it and use it as `recordingDirectory` below.
- Tools → WebSocket Server Settings → enable server and authentication. Do not expose its port to the internet.
- Configure streaming destinations in OBS yourself. Begin with no configured outputs in Anima (`[]`): rehearsal only.
- Install Node >=22.4 and `rsync`. Find Node's absolute path with `command -v node`.

```sh
git clone https://github.com/GBurgardt/anima-studio.git
cd anima-studio
node Scripts/init-server.mjs
```

Edit `~/.config/anima-studio/server.json` locally on the server:
put in the WebSocket password, exact profile/collection, microphone, scenes and recording directory.
The initializer preserves an existing file and starts nothing. Keep permissions `600`.

`node bridge/controller.mjs --discover` lists available scenes, inputs and outputs to help mapping.
It does not start a stream or output. Never publish a real OBS profile or your private config.

## 2. Client: SSH and app

Enable macOS Remote Login on the server for your intended user. Set up key-based SSH;
verify the host fingerprint on the server before accepting it. Do not open router ports.
Example `~/.ssh/config` (replace placeholders):

```sshconfig
Host studio-server
  HostName YOUR_SERVER_LOCAL_HOSTNAME
  User YOUR_SERVER_USER
  IdentityFile ~/.ssh/YOUR_EXISTING_KEY
  IdentitiesOnly yes
```

First verify `ssh -o BatchMode=yes studio-server 'echo connected'` works without a password prompt.
Use a trusted LAN; if accessing remotely, use a private VPN and plan video transport separately.

On the client, macOS 13+ with a Swift 5.9+ toolchain:

```sh
git clone https://github.com/GBurgardt/anima-studio.git
cd anima-studio
bash Scripts/build.sh
open 'dist/Anima Studio Public.app'
```

Settings asks for the SSH alias, absolute Node path, absolute path to
`anima-studio/bridge/controller.mjs` on the server, and its recording directory.
No OBS password needs to be copied to the client. Client config is stored separately
under `~/Library/Application Support/AnimaStudioPublic/client.json`.

Builds are local developer builds, not notarized downloadable releases. If distributing
a binary, set `ANIMA_SIGN_IDENTITY` to your own Developer ID and notarize with Apple.
Do not disable system security globally. This bundle is distinct from the author's private app.

## 3. Send one monitor

- Install official NDI Tools/runtime on the client. The loader checks `/usr/local/lib/libndi.dylib`,
  the SDK runtime location, then NDI Scan Converter's framework. Advanced users can set
  `ANIMA_NDI_LIBRARY` to an absolute compatible runtime path when launching the process.
- Install DistroAV and its required NDI runtime on the server.
- In OBS's Screen scene, create an NDI input named `Desktop NDI`. Set `screenInput` to this name.
- Click a Monitor button on the client; grant Screen Recording permission. If macOS requires it,
  reopen only the client. The sender is named `Anima Studio Monitor`.
- Both machines must be reachable on a network permitting NDI discovery/video. Use Ethernet when practical.
- `Include Studio` controls whether the panel itself appears. Off avoids preview recursion.

This capture is video-only. Connect camera and microphone directly to OBS, or configure
their own supported network sources. Capturing a client monitor does NOT forward its system audio.

## 4. Vertical (optional)

Install Aitum Vertical on the server and create `Vertical Talk`, `Vertical Screen`, `Vertical Pause`.
Reuse the SAME `Desktop NDI` source in Vertical Screen. Set its fit/bounds in OBS for the
screen area; Anima changes only its crops, leaving the horizontal source item untouched.
Enable `vertical.enabled` and fill scene names and the actual canvas UUID in server.json.
Find the UUID via OBS `GetCanvasList` on builds supporting the canvas API, or the local
Aitum configuration. Never copy somebody else's UUID.

Use one vertical canvas for this beta. Configure Aitum to record with OBS if you want both
files. The panel warns if horizontal and vertical recording states differ. Test audio in both.

## 5. Public outputs (optional)

Examples for `outputs` (use only the destinations actually configured in OBS):

```json
[
  {"label":"X", "kind":"main"},
  {"label":"YouTube", "kind":"output", "name":"YOUR_ACTUAL_OBS_OUTPUT_NAME"},
  {"label":"TikTok", "kind":"vertical"}
]
```

For just YouTube: `[{"label":"YouTube","kind":"main"}]`.
For rehearsal: `[]`. Named outputs must already exist and support OBS StartOutput/StopOutput.
Disable plugin automatic/synchronized streaming starts so only the listed destinations start.
The vertical start controls the canvas's configured destinations: enable only those you intend to publish.
Never use this to bypass platform RTMP access requirements.

Anima starts recording before outputs, requires 5 GB free and an unmuted microphone, and
asks you to confirm picture/audio/destinations. That check is YOUR verification, not audio recognition.
If output startup fails, it attempts to stop outputs it started; inspect OBS after any ambiguous timeout.
Event publication and platform latency remain platform-specific.

## 6. Recordings and optional light

Library → Refresh → Bring/Traer copies a closed recording using rsync. Original stays on server.
Files use simple letters/numbers/spaces/dashes/underscores and .mp4/.mkv/.mov extensions.
Copies are manual in this beta; there is no hidden background worker or browser polling.

Pair an Elgato Key Light using Elgato's software, then enter its local hostname in client Settings.
The client must reach it on the LAN. Blank hostname disables the integration. Anima does not pair devices.

## First rehearsal

Leave `outputs: []`. Verify both previews, switch each scene and monitor, exercise vertical zoom,
record ten seconds, stop, bring the file and LISTEN to it. Verify image, audio and lip sync before
ever configuring public outputs. Closing Anima leaves OBS running but stops its own NDI monitor feed.
