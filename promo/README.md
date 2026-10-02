# Demo assets

Native UI screenshots rendered with `--demo --stage 0/1 --snapshot PATH`.
They use labelled example sources, not a live broadcast. No camera, credentials,
real chats or private profiles are included.

Generate a 56-second silent explainer (AppKit + FFmpeg):

```sh
swift promo/render.swift /tmp/anima-demo-frames promo/assets
ffmpeg -framerate 1/7 -i /tmp/anima-demo-frames/%02d.png \
  -f lavfi -i anullsrc=r=48000:cl=stereo \
  -vf "zoompan=z='min(zoom+0.00006,1.012)':d=210:s=1920x1080:fps=30,format=yuv420p" \
  -t 56 -c:v libx264 -preset fast -crf 20 -c:a aac -movflags +faststart demo.mp4
```

Copy draft from `tweet.txt`. Posting is a separate action; this repo does not post to X.
