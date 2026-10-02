import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
export const configPath =
  process.env.ANIMA_CONFIG ||
  path.join(os.homedir(), ".config/anima-studio/server.json");
export function validateConfig(c) {
  if (!c || typeof c !== "object") throw Error("Invalid server configuration");
  for (const k of ["profile", "collection", "microphone", "recordingDirectory"])
    if (typeof c[k] !== "string" || !c[k].trim())
      throw Error(`Configure ${k} in server.json`);
  if (!path.isAbsolute(c.recordingDirectory))
    throw Error("recordingDirectory must be absolute");
  for (const k of ["charla", "pantalla", "pausa"])
    if (typeof c.scenes?.[k] !== "string" || !c.scenes[k])
      throw Error(`Configure scenes.${k}`);
  const url = new URL(c.obs?.url || "ws://127.0.0.1:4455");
  if (
    !["ws:", "wss:"].includes(url.protocol) ||
    !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)
  )
    throw Error(
      "OBS must be loopback on the server; use SSH for remote control",
    );
  if (url.username || url.password)
    throw Error("Do not embed credentials in URLs");
  if (c.vertical?.enabled && !c.vertical.scenes?.pantalla)
    throw Error("Configure vertical scenes");
  if (c.outputs && !Array.isArray(c.outputs))
    throw Error("outputs must be an array");
  for (const o of c.outputs || [])
    if (
      !["main", "output", "vertical"].includes(o.kind) ||
      typeof o.label !== "string" ||
      !o.label ||
      (o.kind === "output" && !o.name)
    )
      throw Error("Invalid output");
  const ids = (c.outputs || []).map((o) =>
    o.kind === "output" ? o.name : o.kind,
  );
  if (new Set(ids).size !== ids.length) throw Error("Duplicate output");
  return c;
}
export async function loadConfig() {
  try {
    return validateConfig(JSON.parse(await fs.readFile(configPath, "utf8")));
  } catch (e) {
    if (e.code === "ENOENT")
      throw Error(
        "Missing ~/.config/anima-studio/server.json. Follow docs/SETUP.md on the OBS server.",
      );
    throw e;
  }
}
