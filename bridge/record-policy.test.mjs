import test from "node:test";
import assert from "node:assert/strict";
import { recordThenStream } from "./record-policy.mjs";
test("recording precedes public start", async () => {
  let recording = false;
  const calls = [];
  const o = {
    call: async (n) => {
      calls.push(n);
      if (n === "StartRecord") recording = true;
      if (n === "GetRecordStatus") return { outputActive: recording };
      if (n === "CallVendorRequest") return { responseData: { recording } };
    },
  };
  await recordThenStream(o, async () => calls.push("AUTHORIZED_STREAM"));
  assert.ok(calls.indexOf("StartRecord") < calls.indexOf("AUTHORIZED_STREAM"));
});
test("a failed public start stops only recording started by this preflight", async () => {
  let recording = false;
  const o = {
    call: async (n) => {
      if (n === "StartRecord") recording = true;
      if (n === "StopRecord") recording = false;
      if (n === "GetRecordStatus") return { outputActive: recording };
      if (n === "CallVendorRequest") return { responseData: { recording } };
    },
  };
  await assert.rejects(() =>
    recordThenStream(o, async () => {
      throw Error("failure");
    }),
  );
  assert.equal(recording, false);
});
