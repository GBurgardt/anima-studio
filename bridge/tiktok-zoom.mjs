// Scene-item crop only: never mutate the shared NDI input or horizontal output.
export const zoomTarget = { sceneName: "Vertical Screen" };
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
export function zoomState(t) {
  const w = t.sourceWidth,
    h = t.sourceHeight;
  if (!(w > 0 && h > 0))
    throw Error("La pantalla compartida todavía no tiene señal.");
  const left = t.cropLeft || 0,
    right = t.cropRight || 0,
    top = t.cropTop || 0,
    bottom = t.cropBottom || 0;
  return {
    factor: w / Math.max(1, w - left - right),
    x: (left + (w - left - right) / 2) / w,
    y: (top + (h - top - bottom) / 2) / h,
  };
}
export function zoomCrop(t, action) {
  const s = zoomState(t);
  if (!["in", "out", "reset", "left", "right", "up", "down"].includes(action))
    throw Error("Zoom inválido.");
  let z = clamp(s.factor, 1, 4),
    x = s.x,
    y = s.y;
  if (action === "in") z = clamp(z + 0.25, 1, 4);
  if (action === "out") z = clamp(z - 0.25, 1, 4);
  if (action === "reset") {
    z = 1;
    x = y = 0.5;
  }
  if (action === "left") x -= 0.1 / z;
  if (action === "right") x += 0.1 / z;
  if (action === "up") y -= 0.1 / z;
  if (action === "down") y += 0.1 / z;
  const w = t.sourceWidth,
    h = t.sourceHeight,
    cw = Math.round(w / z),
    ch = Math.round(h / z);
  const l = clamp(Math.round(x * w - cw / 2), 0, w - cw),
    top = clamp(Math.round(y * h - ch / 2), 0, h - ch);
  return {
    cropLeft: l,
    cropRight: w - cw - l,
    cropTop: top,
    cropBottom: h - ch - top,
  };
}
async function item(o) {
  const list = await o.call("GetSceneItemList", zoomTarget);
  const matches = list.sceneItems.filter(
    (i) => i.sourceName === "Screen" && i.inputKind === "ndi_source",
  );
  if (matches.length !== 1)
    throw Error(
      "No pude identificar la pantalla de TikTok; no se modificó nada.",
    );
  return matches[0];
}
export async function currentZoom(o) {
  return zoomState((await item(o)).sceneItemTransform);
}
export async function applyZoom(o, action) {
  const i = await item(o),
    before = i.sceneItemTransform;
  const crop = zoomCrop(before, action),
    target = { ...zoomTarget, sceneItemId: i.sceneItemId };
  await o.call("SetSceneItemTransform", {
    ...target,
    sceneItemTransform: crop,
  });
  try {
    const after = (await o.call("GetSceneItemTransform", target))
      .sceneItemTransform;
    if (Object.keys(crop).some((k) => Math.abs(after[k] - crop[k]) > 1))
      throw Error("No se pudo verificar el zoom.");
    return zoomState(after);
  } catch (e) {
    await o.call("SetSceneItemTransform", {
      ...target,
      sceneItemTransform: Object.fromEntries(
        Object.keys(crop).map((k) => [k, before[k] || 0]),
      ),
    });
    throw e;
  }
}
