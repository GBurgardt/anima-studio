# Optional clean editing master

Use shared content scenes rather than copied camera layouts. This avoids drift when you
adjust the framing later. This is an OBS setup, not an automatic clip editor.

1. Create `Talk Content`, `Screen Content`, `Pause Content` with your actual video/layouts.
2. Live scenes `Talk`, `Screen`, `Pause` each contain the matching content scene as a
   full-size nested scene. Add LIVE text/overlays only to these outer live scenes.
3. Create `Clean Master`. Add the three content scenes as full-size nested sources.
4. Tools → Scripts → add `bridge/clean-master.lua`. Set the collection and scene names.
   The helper toggles only the content items inside Clean Master to follow the live scene.
5. Install the separate [Source Record plugin](https://obsproject.com/forum/resources/source-record.1285/).
   Add its recording filter to Clean Master. Set record mode to follow OBS recording,
   a suitable hardware encoder, destination folder and audio track. Use a distinct filename prefix.
6. Record a local rehearsal. Check each scene, overlays absent, updated framing, and AUDIO
   in the additional file. Do not assume a silent source automatically includes your microphone.

Keep the actual layout changes inside the shared CONTENT scenes. Transforms or filters applied
only to the outer live scene deliberately do not affect the clean master. This adds an encoder;
check load, disk and recording behavior on your own hardware before a public stream.

The script never starts outputs, creates sources or changes encoding settings. If scene names
do not match, fix the mapping rather than expecting it to discover your layout.
