import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";
import { handle, MAX_BYTES, resetMemoryLimits, TOUCH_EVERY_MS, TTL_SECONDS } from "../src/relay.js";

// In-memory stand-in for a KV namespace (only what relay.js uses).
class FakeKV {
  constructor() {
    this.items = new Map();
    this.puts = [];
  }
  async put(key, value, options = {}) {
    this.puts.push({ key, options });
    this.items.set(key, { value, metadata: options.metadata ?? null });
  }
  async get(key) {
    const item = this.items.get(key);
    return item ? item.value : null;
  }
  async getWithMetadata(key) {
    const item = this.items.get(key);
    return item ? { value: item.value, metadata: item.metadata } : { value: null, metadata: null };
  }
  async delete(key) {
    this.items.delete(key);
  }
}

const ID = "a".repeat(64);
const BASE = "https://relay.example.workers.dev";
let env;

beforeEach(() => {
  resetMemoryLimits();
  env = { RELAY: new FakeKV() };
});

const request = (path, init = {}) => new Request(`${BASE}${path}`, init);
const put = (body, now) => handle(request(`/v1/items/${ID}`, { method: "PUT", body }), env, null, now);
const get = (headers = {}, now = 2000) => handle(request(`/v1/items/${ID}`, { headers }), env, null, now);

test("health and unknown paths", async () => {
  assert.equal((await handle(request("/"), env, null)).status, 200);
  assert.equal((await handle(request("/v1/items/short"), env, null)).status, 404);
  assert.equal((await handle(request(`/v1/items/${"A".repeat(64)}`), env, null)).status, 404);
});

test("upload then download round-trips the bytes with an ETag", async () => {
  const response = await put(new Uint8Array([1, 2, 3]), 1000);
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { version: "1000", size: 3 });
  assert.equal(env.RELAY.puts[0].options.expirationTtl, TTL_SECONDS);

  const download = await get();
  assert.equal(download.status, 200);
  assert.equal(download.headers.get("ETag"), '"1000"');
  assert.deepEqual([...new Uint8Array(await download.arrayBuffer())], [1, 2, 3]);
});

test("missing item is 404, matching ETag is 304", async () => {
  assert.equal((await get()).status, 404);
  await put(new Uint8Array([9]), 1000);
  assert.equal((await get({ "If-None-Match": '"1000"' })).status, 304);
  assert.equal((await get({ "If-None-Match": '"999"' })).status, 200);
});

test("rejects bodies over 1 MiB and empty bodies", async () => {
  assert.equal((await put(new Uint8Array(MAX_BYTES + 1), 1)).status, 413);
  assert.equal((await put(new Uint8Array(0), 1)).status, 400);
  assert.equal(env.RELAY.items.size, 0);
});

test("status reports upload and the last widget download", async () => {
  const status = async () => (await handle(request(`/v1/items/${ID}/status`), env, null, 5000)).json();
  assert.deepEqual(await status(), { exists: false, size: null, uploaded: null, lastDownload: null });
  await put(new Uint8Array([1, 2]), 1000);
  assert.deepEqual(await status(), { exists: true, size: 2, uploaded: 1000, lastDownload: null });
  await get({}, 3000);
  assert.equal((await status()).lastDownload, 3000);
});

test("access re-puts an old item so it doesn't expire, at most once a day", async () => {
  await put(new Uint8Array([1]), 1000);
  const before = env.RELAY.puts.length;
  await get({ "If-None-Match": '"1000"' }, 1000 + 60_000);
  assert.equal(env.RELAY.puts.length, before);
  await get({ "If-None-Match": '"1000"' }, 1000 + TOUCH_EVERY_MS + 1);
  assert.equal(env.RELAY.puts.length, before + 1);
  assert.equal(env.RELAY.items.get(`i:${ID}`).metadata.touched, 1000 + TOUCH_EVERY_MS + 1);
  assert.equal(env.RELAY.items.get(`i:${ID}`).metadata.v, "1000");
});

test("rate limits per ID", async () => {
  let last;
  for (let i = 0; i < 61; i++) last = await get({}, 1000);
  assert.equal(last.status, 429);
  assert.equal(last.headers.get("Retry-After"), "60");
  // Another minute: allowed again.
  assert.equal((await get({}, 1000 + 61_000)).status, 404);
});

test("uses the rate-limit binding when present", async () => {
  env.LIMITER = { limit: async () => ({ success: false }) };
  assert.equal((await get()).status, 429);
});

test("delete removes the item and its download time", async () => {
  await put(new Uint8Array([1]), 1000);
  await get({}, 2000);
  const response = await handle(request(`/v1/items/${ID}`, { method: "DELETE" }), env, null, 3000);
  assert.equal(response.status, 200);
  assert.equal(env.RELAY.items.size, 0);
});

test("rejects other methods", async () => {
  assert.equal((await handle(request(`/v1/items/${ID}`, { method: "POST" }), env, null)).status, 405);
  assert.equal((await handle(request(`/v1/items/${ID}/status`, { method: "PUT", body: "x" }), env, null)).status, 405);
});
