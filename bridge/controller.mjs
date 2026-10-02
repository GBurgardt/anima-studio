import fs from "node:fs/promises";
import path from "node:path";
import readline from "node:readline";
import { loadConfig } from "./config.mjs";
import { connectOBS } from "./obs-client.mjs";
import { zoomCrop, zoomState } from "./tiktok-zoom.mjs";
import { selectMonitorSource } from "./monitor-source.mjs";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
export const commands = [
  "status",
  "prepare",
  "scene",
  "tiktok-zoom",
  "monitor-source",
  "record-start",
  "record-stop",
  "mute",
  "library",
  "live-start",
  "live-stop",
];
export function validateIntent(m) {
  if (!commands.includes(m.cmd)) throw Error("Unsupported action");
  if (
    m.cmd === "live-start" &&
    (m.confirmation !== "START_CONFIGURED_OUTPUTS" ||
      m.checkedPictureAndVoice !== true)
  )
    throw Error("Confirm picture, audio and configured destinations first");
  if (
    m.cmd === "live-stop" &&
    m.confirmation !== "STOP_PUBLIC_ALL_DESTINATIONS"
  )
    throw Error("Confirm stopping outputs first");
}
export async function createController(c, obs) {
  let peak = -96;
  const vertical = () =>
    obs
      .call("CallVendorRequest", {
        vendorName: "aitum-vertical-canvas",
        requestType: "status",
      })
      .then((r) => r.responseData);
  const canvas = () =>
    c.vertical?.canvasUuid ? { canvasUuid: c.vertical.canvasUuid } : {};
  async function check() {
    const [p, s] = await Promise.all([
      obs.call("GetProfileList"),
      obs.call("GetSceneCollectionList"),
    ]);
    if (
      p.currentProfileName !== c.profile ||
      s.currentSceneCollectionName !== c.collection
    )
      throw Error(
        "OBS profile/collection does not match server.json; no changes made",
      );
  }
  async function outputs() {
    const [s, list, v] = await Promise.all([
      obs.call("GetStreamStatus"),
      obs.call("GetOutputList"),
      c.vertical?.enabled ? vertical() : {},
    ]);
    return (c.outputs || []).map((o) => ({
      ...o,
      active:
        o.kind === "main"
          ? s.outputActive
          : o.kind === "vertical"
            ? !!v.streaming
            : !!list.outputs.find((x) => x.outputName === o.name)?.outputActive,
    }));
  }
  async function zoomItem() {
    if (!c.vertical?.enabled || !c.screenInput)
      throw Error("Configure vertical screen input first");
    const target = { sceneName: c.vertical.scenes.pantalla, ...canvas() };
    const list = await obs.call("GetSceneItemList", target);
    const matches = list.sceneItems.filter(
      (i) => i.sourceName === c.screenInput,
    );
    if (matches.length !== 1)
      throw Error("Vertical screen item missing or ambiguous");
    return {
      ...target,
      sceneItemId: matches[0].sceneItemId,
      transform: matches[0].sceneItemTransform,
    };
  }
  async function snapshot() {
    const [r, s, stats, mute, v, d] = await Promise.all([
      obs.call("GetRecordStatus"),
      obs.call("GetCurrentProgramScene"),
      obs.call("GetStats"),
      obs.call("GetInputMute", { inputName: c.microphone }),
      c.vertical?.enabled ? vertical() : {},
      outputs(),
    ]);
    let vscene = "";
    if (c.vertical?.enabled)
      vscene = (
        await obs.call("CallVendorRequest", {
          vendorName: "aitum-vertical-canvas",
          requestType: "current_scene",
        })
      ).responseData.scene;
    const capture = (sourceName, extra = {}) =>
      obs
        .call("GetSourceScreenshot", {
          sourceName,
          imageFormat: "jpg",
          imageWidth: extra.canvasUuid ? 480 : 800,
          imageCompressionQuality: 65,
          ...extra,
        })
        .then((x) => x.imageData)
        .catch(() => null);
    const [horizontal, portrait] = await Promise.all([
      capture(s.currentProgramSceneName),
      vscene ? capture(vscene, canvas()) : null,
    ]);
    const z = await zoomItem()
      .then((i) => zoomState(i.transform))
      .catch(() => null);
    const platform = (label) => ({
      enabled: d.some((o) => o.label === label),
      configured: d.some((o) => o.label === label),
      active: d.some((o) => o.label === label && o.active),
      dashboardURL:
        label === "YouTube"
          ? "https://studio.youtube.com"
          : "https://studio.x.com/live",
      message: "",
    });
    return {
      scene: s.currentProgramSceneName,
      sceneKey: Object.keys(c.scenes).find(
        (k) => c.scenes[k] === s.currentProgramSceneName,
      ),
      verticalScene: vscene,
      verticalEnabled: !!c.vertical?.enabled,
      recording: r.outputActive,
      recordingVertical: !!v.recording,
      live: d.some((o) => o.active),
      xActive: platform("X").active,
      tiktokOutputActive: platform("TikTok").active,
      youtube: platform("YouTube"),
      x: platform("X"),
      timecode: r.outputTimecode || "",
      muted: mute.inputMuted,
      peak,
      fps: stats.activeFps,
      cpu: stats.cpuUsage,
      freeGB: stats.availableDiskSpace / 1024,
      simulated: false,
      horizontal,
      portrait,
      tiktokZoom: z,
      metrics: {},
      destinations: d.map((o) => o.label),
    };
  }
  async function toggle(o, start) {
    if (o.kind === "main")
      return obs.call(start ? "StartStream" : "StopStream");
    if (o.kind === "output")
      return obs.call(start ? "StartOutput" : "StopOutput", {
        outputName: o.name,
      });
    return obs.call("CallVendorRequest", {
      vendorName: "aitum-vertical-canvas",
      requestType: start ? "start_streaming" : "stop_streaming",
    });
  }
  async function library() {
    const recording = (await obs.call("GetRecordStatus")).outputActive;
    const root = await fs.realpath(c.recordingDirectory);
    const files = [];
    for (const name of await fs.readdir(root)) {
      if (!/^[A-Za-z0-9][A-Za-z0-9 ._-]*\.(mp4|mkv|mov)$/i.test(name)) continue;
      const p = path.join(root, name),
        st = await fs.lstat(p);
      if (!st.isFile() || st.isSymbolicLink()) continue;
      files.push({
        name,
        path: p,
        size: st.size,
        modified: st.mtime.toISOString(),
        ready: !recording && Date.now() - st.mtimeMs > 10000,
      });
    }
    return {
      files: files
        .sort((a, b) => b.modified.localeCompare(a.modified))
        .slice(0, 100),
      streams: [],
      sync: {
        phase: "manual",
        message: "Traer copia el archivo; el original queda en el servidor.",
      },
    };
  }
  return {
    event(e) {
      if (e.eventType === "InputVolumeMeters") {
        const i = e.eventData.inputs?.find((i) => i.inputName === c.microphone);
        if (i?.inputLevelsMul)
          peak = Math.max(
            -96,
            ...i.inputLevelsMul.map(
              (x) => 20 * Math.log10(Math.max(x[1], 1e-8)),
            ),
          );
      }
    },
    async dispatch(m) {
      validateIntent(m);
      await check();
      if (m.cmd === "library") return library();
      if (m.cmd === "scene") {
        if (!Object.hasOwn(c.scenes, m.scene)) throw Error("Invalid scene");
        const before = await obs.call("GetCurrentProgramScene");
        await obs.call("SetCurrentProgramScene", {
          sceneName: c.scenes[m.scene],
        });
        try {
          if (c.vertical?.enabled)
            await obs.call("CallVendorRequest", {
              vendorName: "aitum-vertical-canvas",
              requestType: "switch_scene",
              requestData: { scene: c.vertical.scenes[m.scene] },
            });
        } catch (e) {
          await obs.call("SetCurrentProgramScene", {
            sceneName: before.currentProgramSceneName,
          });
          throw e;
        }
      }
      if (m.cmd === "monitor-source") {
        if (!c.screenInput) throw Error("Configure screenInput");
        await selectMonitorSource(obs, m.source, c.screenInput);
      }
      if (m.cmd === "tiktok-zoom") {
        const i = await zoomItem(),
          crop = zoomCrop(i.transform, m.action);
        const { transform, ...target } = i;
        await obs.call("SetSceneItemTransform", {
          ...target,
          sceneItemTransform: crop,
        });
        const after = (await obs.call("GetSceneItemTransform", target))
          .sceneItemTransform;
        if (Object.keys(crop).some((k) => Math.abs(crop[k] - after[k]) > 1)) {
          await obs.call("SetSceneItemTransform", {
            ...target,
            sceneItemTransform: Object.fromEntries(
              Object.keys(crop).map((k) => [k, transform[k] || 0]),
            ),
          });
          throw Error("Zoom verification failed");
        }
      }
      if (m.cmd === "mute") {
        if (typeof m.muted !== "boolean") throw Error("Invalid mute value");
        await obs.call("SetInputMute", {
          inputName: c.microphone,
          inputMuted: m.muted,
        });
      }
      if (m.cmd === "record-start" || m.cmd === "record-stop") {
        if ((await outputs()).some((o) => o.active))
          throw Error("Use live controls while transmitting");
        await obs.call(m.cmd === "record-start" ? "StartRecord" : "StopRecord");
      }
      if (m.cmd === "live-start") {
        const before = await outputs();
        if (!before.length) throw Error("No destinations configured");
        if (before.some((o) => o.active))
          throw Error("Outputs already active; inspect OBS");
        const stats = await obs.call("GetStats");
        if (stats.availableDiskSpace < 5120)
          throw Error("At least 5 GB free required");
        const mic = await obs.call("GetInputMute", { inputName: c.microphone });
        if (mic.inputMuted) throw Error("Microphone is muted");
        const owned = !(await obs.call("GetRecordStatus")).outputActive;
        const started = [];
        try {
          if (owned) await obs.call("StartRecord");
          if (!(await obs.call("GetRecordStatus")).outputActive)
            throw Error("Recording did not start");
          for (const o of before) {
            started.push(o);
            await toggle(o, true);
          }
          let ready = false;
          for (let n = 0; n < 12; n++) {
            if ((await outputs()).every((o) => o.active)) {
              ready = true;
              break;
            }
            await sleep(500);
          }
          if (!ready)
            throw Error("Not all outputs started; inspect OBS and platforms");
        } catch (e) {
          let clean = true;
          for (const o of started.reverse())
            try {
              await toggle(o, false);
            } catch {
              clean = false;
            }
          if (owned && clean) await obs.call("StopRecord").catch(() => {});
          throw e;
        }
      }
      if (m.cmd === "live-stop") {
        const errors = [];
        for (const o of await outputs())
          if (o.active)
            try {
              await toggle(o, false);
            } catch {
              errors.push(o.label);
            }
        for (let n = 0; n < 12; n++) {
          if (!(await outputs()).some((o) => o.active)) break;
          await sleep(500);
        }
        if ((await outputs()).some((o) => o.active) || errors.length)
          throw Error(
            "Could not confirm all outputs stopped. Recording preserved; inspect OBS.",
          );
        if ((await obs.call("GetRecordStatus")).outputActive)
          await obs.call("StopRecord");
      }
      return snapshot();
    },
  };
}
if (process.argv.includes("--serve") || process.argv.includes("--discover")) {
  let obs, ctl;
  async function ready() {
    if (ctl) return ctl;
    const c = await loadConfig();
    obs = await connectOBS(c.obs || {}, { onEvent: (e) => ctl?.event(e) });
    ctl = await createController(c, obs);
    return ctl;
  }
  if (process.argv.includes("--discover")) {
    try {
      await ready();
      const names = {
        profiles: await obs.call("GetProfileList"),
        collections: await obs.call("GetSceneCollectionList"),
        scenes: await obs.call("GetSceneList"),
        inputs: await obs.call("GetInputList"),
        outputs: await obs.call("GetOutputList"),
      };
      console.log(JSON.stringify(names, null, 2));
    } finally {
      obs?.close();
    }
  } else {
    for await (const line of readline.createInterface({
      input: process.stdin,
      crlfDelay: Infinity,
    })) {
      let m;
      try {
        if (line.length > 16384) throw Error("Request too large");
        m = JSON.parse(line);
        validateIntent(m);
        const data = await (await ready()).dispatch(m);
        process.stdout.write(
          JSON.stringify({ id: m.id, ok: true, data }) + "\n",
        );
      } catch (e) {
        obs?.close();
        obs = null;
        ctl = null;
        process.stdout.write(
          JSON.stringify({ id: m?.id, ok: false, error: e.message }) + "\n",
        );
      }
    }
    obs?.close();
  }
}
