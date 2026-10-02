import test from "node:test";
import assert from "node:assert/strict";
import { createController } from "./controller.mjs";
const cfg = {
  profile: "Test",
  collection: "Test",
  scenes: { charla: "Talk", pantalla: "Screen", pausa: "Pause" },
  microphone: "Mic",
  outputs: [{ kind: "main", label: "YouTube" }],
};
function mock({ recording = false, muted = false, failStart = false } = {}) {
  let live = false,
    scene = "Talk";
  const calls = [];
  return {
    calls,
    call: async (m, a) => {
      calls.push({ m, a });
      switch (m) {
        case "GetProfileList":
          return { currentProfileName: "Test" };
        case "GetSceneCollectionList":
          return { currentSceneCollectionName: "Test" };
        case "GetRecordStatus":
          return { outputActive: recording, outputTimecode: "00:00:10" };
        case "GetStreamStatus":
          return { outputActive: live };
        case "GetOutputList":
          return { outputs: [] };
        case "GetStats":
          return { availableDiskSpace: 10240, activeFps: 30, cpuUsage: 1 };
        case "GetInputMute":
          return { inputMuted: muted };
        case "GetCurrentProgramScene":
          return { currentProgramSceneName: scene };
        case "GetSourceScreenshot":
          return { imageData: null };
        case "StartRecord":
          recording = true;
          return {};
        case "StopRecord":
          recording = false;
          return {};
        case "StartStream":
          if (failStart) throw Error("failed");
          live = true;
          return {};
        case "StopStream":
          live = false;
          return {};
        case "SetCurrentProgramScene":
          scene = a.sceneName;
          return {};
        default:
          throw Error(m);
      }
    },
  };
}
const intent = {
  cmd: "live-start",
  confirmation: "START_CONFIGURED_OUTPUTS",
  checkedPictureAndVoice: true,
};
test("recording starts before configured public output; stop verifies then closes recording", async () => {
  const o = mock(),
    c = await createController(cfg, o);
  assert.equal((await c.dispatch(intent)).live, true);
  assert.ok(
    o.calls.findIndex((x) => x.m === "StartRecord") <
      o.calls.findIndex((x) => x.m === "StartStream"),
  );
  const s = await c.dispatch({
    cmd: "live-stop",
    confirmation: "STOP_PUBLIC_ALL_DESTINATIONS",
  });
  assert.equal(s.live, false);
  assert.equal(s.recording, false);
});
test("muted microphone never starts anything", async () => {
  const o = mock({ muted: true }),
    c = await createController(cfg, o);
  await assert.rejects(c.dispatch(intent));
  assert.ok(!o.calls.some((x) => x.m.startsWith("Start")));
});
test("failed start preserves pre-existing recording", async () => {
  const o = mock({ recording: true, failStart: true }),
    c = await createController(cfg, o);
  await assert.rejects(c.dispatch(intent));
  assert.ok(!o.calls.some((x) => x.m === "StopRecord"));
});
test("failed start rolls back owned recording", async () => {
  const o = mock({ failStart: true }),
    c = await createController(cfg, o);
  await assert.rejects(c.dispatch(intent));
  assert.ok(o.calls.some((x) => x.m === "StopRecord"));
});
test("invalid scene cannot modify OBS", async () => {
  const o = mock(),
    c = await createController(cfg, o);
  await assert.rejects(c.dispatch({ cmd: "scene", scene: "unknown" }));
  assert.ok(!o.calls.some((x) => x.m.startsWith("Set")));
});
test("camera-free scene switch maps arbitrary names", async () => {
  const o = mock(),
    c = await createController(cfg, o);
  assert.equal(
    (await c.dispatch({ cmd: "scene", scene: "pantalla" })).scene,
    "Screen",
  );
});
