import { createHash, randomUUID } from "node:crypto";
export async function connectOBS(config, { onEvent = () => {} } = {}) {
  const ws = new WebSocket(config.url || "ws://127.0.0.1:4455");
  const pending = new Map();
  let finish;
  const sha = (s) => createHash("sha256").update(s).digest("base64");
  const ready = new Promise((resolve, reject) => {
    finish = { resolve, reject };
  });
  const timer = setTimeout(() => {
    finish.reject(Error("OBS connection timed out"));
    ws.close();
  }, 8000);
  function closed() {
    clearTimeout(timer);
    finish.reject(Error("OBS disconnected"));
    for (const p of pending.values()) {
      clearTimeout(p.timer);
      p.reject(Error("OBS disconnected"));
    }
    pending.clear();
  }
  ws.addEventListener("close", closed);
  ws.addEventListener("error", closed);
  ws.addEventListener("message", (e) => {
    let m;
    try {
      m = JSON.parse(e.data);
    } catch {
      return;
    }
    if (m.op === 0) {
      const d = { rpcVersion: 1, eventSubscriptions: 65536 };
      if (m.d.authentication)
        d.authentication = sha(
          sha((config.password || "") + m.d.authentication.salt) +
            m.d.authentication.challenge,
        );
      ws.send(JSON.stringify({ op: 1, d }));
    }
    if (m.op === 2) {
      clearTimeout(timer);
      finish.resolve();
    }
    if (m.op === 5) onEvent(m.d);
    if (m.op === 7) {
      const p = pending.get(m.d.requestId);
      if (!p) return;
      pending.delete(m.d.requestId);
      clearTimeout(p.timer);
      m.d.requestStatus.result
        ? p.resolve(m.d.responseData || {})
        : p.reject(
            Error(`${m.d.requestType} failed (${m.d.requestStatus.code})`),
          );
    }
  });
  await ready;
  return {
    close: () => ws.close(),
    call(requestType, requestData = {}) {
      if (ws.readyState !== WebSocket.OPEN)
        return Promise.reject(Error("OBS disconnected"));
      const requestId = randomUUID();
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          pending.delete(requestId);
          reject(Error(`${requestType} timed out; verify OBS before retrying`));
        }, 10000);
        pending.set(requestId, { resolve, reject, timer });
        ws.send(
          JSON.stringify({ op: 6, d: { requestType, requestData, requestId } }),
        );
      });
    },
  };
}
