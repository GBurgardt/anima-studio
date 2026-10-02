# Verification and limits

Public beta verification:

- Node tests: config validation, loopback restriction, explicit live confirmation,
  wrong-profile guard, optional-plugin status, scene selection, startup order,
  rollback ownership, mute guard and bounded vertical crop.
- Swift tests: SSH input validation/quoting, light decoding and bounds,
  capture dimensions and own-app exclusion.
- Public bridge successfully read a running OBS server's status and horizontal preview
  without changing scenes, opening a camera, recording or streaming.
- Native macOS build tested locally. `ci-workflow.example.yml` is a ready-to-enable
  GitHub Actions template; CI is not enabled by this release because the publishing
  credential does not have workflow permission. Local tests are not presented as CI runs.

Mocks test mutation paths; they are NOT proof of live platform reception. No public
broadcast was started for QA. Full fresh-install hardware verification of every plugin,
OS and account combination is not claimed. Follow the ten-second rehearsal checklist.

The promotional demo uses clearly labelled example sources, not a staged public broadcast.
NDI, Aitum, Source Record and Elgato are optional external integrations; test them on your
own setup. Server WebSocket failure preserves the last known recording/output state;
verify OBS before retrying an action with an uncertain result.
