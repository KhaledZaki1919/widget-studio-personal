// Widget Studio P relay (docs/personal.md): stores end-to-end encrypted items in KV.
// The server never sees the pairing code: an item's ID is a hash derived from it, and the body
// is AES-GCM ciphertext made on the phone. No accounts, no secrets, no logs of contents.
//
//   PUT    /v1/items/<id>         body = ciphertext (max 1 MiB) -> {version, size}
//   GET    /v1/items/<id>         If-None-Match -> 200 body + ETag | 304 | 404
//   GET    /v1/items/<id>/status  -> {exists, size, uploaded, lastDownload} (ms since 1970)
//   DELETE /v1/items/<id>
//
// KV keys: "i:<id>" = ciphertext with metadata {v, up, touched, size}; "r:<id>" = last time a
// widget downloaded it. Both expire 30 days after the last access (re-put at most once a day,
// which keeps KV writes within the free plan).

export const MAX_BYTES = 1024 * 1024;
export const TTL_SECONDS = 30 * 24 * 3600;
export const TOUCH_EVERY_MS = 24 * 3600 * 1000;
// Fallback when the rate-limit bindings are missing (per isolate only).
export const MEMORY_LIMIT = { requests: 60, writes: 10, windowMs: 60_000 };

const ITEM = /^\/v1\/items\/([0-9a-f]{64})(\/status)?$/;
const memory = new Map();

export async function handle(request, env, ctx, now = Date.now()) {
  const url = new URL(request.url);
  if (url.pathname === "/" || url.pathname === "/v1/health") {
    return json({ ok: true, service: "widget-studio-relay" });
  }
  const match = url.pathname.match(ITEM);
  if (!match) return json({ error: "not found" }, 404);
  const [, id, status] = match;
  const method = request.method;
  const writes = method === "PUT" || method === "DELETE";
  if (status && method !== "GET") return json({ error: "method not allowed" }, 405);
  if (!["GET", "PUT", "DELETE"].includes(method)) return json({ error: "method not allowed" }, 405);

  // Per ID for everything; per client IP as well for writes.
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  if (!(await allowed(env.LIMITER, `id:${id}`, MEMORY_LIMIT.requests, now)) ||
      (writes && !(await allowed(env.WRITE_LIMITER, `ip:${ip}`, MEMORY_LIMIT.writes, now)))) {
    return json({ error: "rate limited" }, 429, { "Retry-After": "60" });
  }

  if (status) return itemStatus(env, id);
  if (method === "PUT") return put(request, env, id, now);
  if (method === "DELETE") {
    await Promise.all([env.RELAY.delete(`i:${id}`), env.RELAY.delete(`r:${id}`)]);
    return json({ deleted: true });
  }
  return get(request, env, ctx, id, now);
}

async function put(request, env, id, now) {
  const declared = Number(request.headers.get("Content-Length") || "0");
  if (declared > MAX_BYTES) return json({ error: "too large" }, 413);
  const body = await request.arrayBuffer();
  if (body.byteLength > MAX_BYTES) return json({ error: "too large" }, 413);
  if (body.byteLength === 0) return json({ error: "empty body" }, 400);
  const version = String(now);
  const metadata = { v: version, up: now, touched: now, size: body.byteLength };
  await env.RELAY.put(`i:${id}`, body, { metadata, expirationTtl: TTL_SECONDS });
  return json({ version, size: body.byteLength }, 201);
}

async function get(request, env, ctx, id, now) {
  const { value, metadata } = await env.RELAY.getWithMetadata(`i:${id}`, { type: "arrayBuffer" });
  if (value === null || !metadata) return json({ error: "not found" }, 404);
  const etag = `"${metadata.v}"`;
  const work = [];
  if (now - (metadata.touched || 0) > TOUCH_EVERY_MS) {
    work.push(env.RELAY.put(`i:${id}`, value, { metadata: { ...metadata, touched: now }, expirationTtl: TTL_SECONDS }));
  }
  if (request.headers.get("If-None-Match") === etag) {
    defer(ctx, work);
    return new Response(null, { status: 304, headers: { ETag: etag } });
  }
  work.push(env.RELAY.put(`r:${id}`, String(now), { expirationTtl: TTL_SECONDS }));
  defer(ctx, work);
  return new Response(value, {
    status: 200,
    headers: { "Content-Type": "application/octet-stream", ETag: etag, "Cache-Control": "no-store" },
  });
}

async function itemStatus(env, id) {
  const [{ value, metadata }, read] = await Promise.all([
    env.RELAY.getWithMetadata(`i:${id}`, { type: "arrayBuffer" }),
    env.RELAY.get(`r:${id}`),
  ]);
  const exists = value !== null && !!metadata;
  return json({
    exists,
    size: exists ? metadata.size : null,
    uploaded: exists ? metadata.up : null,
    lastDownload: read ? Number(read) : null,
  });
}

async function allowed(limiter, key, limit, now) {
  if (limiter && typeof limiter.limit === "function") {
    const { success } = await limiter.limit({ key });
    return success;
  }
  const windowStart = now - MEMORY_LIMIT.windowMs;
  const hits = (memory.get(key) || []).filter((time) => time > windowStart);
  if (hits.length >= limit) {
    memory.set(key, hits);
    return false;
  }
  hits.push(now);
  memory.set(key, hits);
  return true;
}

function defer(ctx, work) {
  if (work.length === 0) return;
  const all = Promise.all(work).catch(() => {});
  if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(all);
}

function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...headers },
  });
}

export function resetMemoryLimits() {
  memory.clear();
}
