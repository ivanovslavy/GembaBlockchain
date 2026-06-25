#!/usr/bin/env node
// Track 3 — rate-limit probe (MODEST, NON-DESTRUCTIVE).
//
// Fires ONE short controlled burst of ~60 eth_blockNumber requests within ~3s at
// rpc1.gembascan.io and reports whether / when HTTP 429 or a Cloudflare challenge
// kicks in (documented nginx limit: 25 req/s). This is a single probe burst — not an
// attack, not sustained load. ~60 requests total, then it stops.
//
// Run: node security/track3-rpc-infra/ratelimit-probe.js
// Appends a summary to security/results/rpc-fuzz.txt and prints to stdout.
//
// See docs/security-pentest-2026-06-24.md (Track 3).

import { appendFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const RESULTS = join(__dirname, "..", "results", "rpc-fuzz.txt");

const TARGET = "https://rpc1.gembascan.io";
const TOTAL = 60; // total requests in the burst
const WINDOW_MS = 3000; // spread them over ~3s  => ~20 req/s (around the 25 r/s limit)
const REQ_TIMEOUT_MS = 8000;

const body = JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_blockNumber", params: [] });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// crude Cloudflare-challenge / block detection on body or headers
function detectCloudflare(status, headers, text) {
  const server = (headers.get("server") || "").toLowerCase();
  const cfRay = headers.get("cf-ray");
  const cfMitigated = headers.get("cf-mitigated");
  const looksChallenge =
    /just a moment|cf-challenge|challenge-platform|attention required|cloudflare/i.test(text || "") &&
    !/jsonrpc/i.test(text || "");
  if (status === 403 && (cfRay || /cloudflare/.test(server))) return "cloudflare-403";
  if (status === 503 && (cfRay || /cloudflare/.test(server))) return "cloudflare-503";
  if (cfMitigated) return `cf-mitigated:${cfMitigated}`;
  if (looksChallenge) return "cf-challenge-page";
  return null;
}

async function oneReq(idx) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), REQ_TIMEOUT_MS);
  const started = Date.now();
  try {
    const res = await fetch(TARGET, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      signal: ctrl.signal,
    });
    const text = await res.text();
    const cf = detectCloudflare(res.status, res.headers, text);
    const retryAfter = res.headers.get("retry-after");
    return { idx, status: res.status, ms: Date.now() - started, cf, retryAfter, ok: true };
  } catch (e) {
    return { idx, status: 0, ms: Date.now() - started, err: e.name === "AbortError" ? "timeout" : e.message, ok: false };
  } finally {
    clearTimeout(t);
  }
}

const lines = [];
const log = (s) => {
  lines.push(s);
  console.log(s);
};

async function run() {
  log("");
  log("──────── RATE-LIMIT PROBE ────────");
  log(`# Target: ${TARGET}`);
  log(`# Burst: ${TOTAL} eth_blockNumber requests over ~${WINDOW_MS}ms (~${Math.round((TOTAL / WINDOW_MS) * 1000)} req/s)`);
  log(`# Run: ${new Date().toISOString()}`);

  const interval = WINDOW_MS / TOTAL;
  const inflight = [];
  const t0 = Date.now();
  for (let i = 0; i < TOTAL; i++) {
    inflight.push(oneReq(i));
    await sleep(interval); // pace the dispatch; requests still overlap on the wire
  }
  const results = await Promise.all(inflight);
  const elapsed = Date.now() - t0;

  const byStatus = {};
  let first429 = null;
  let firstCf = null;
  let firstErr = null;
  const latencies = [];

  for (const r of results) {
    const key = r.ok ? String(r.status) : `ERR:${r.err}`;
    byStatus[key] = (byStatus[key] || 0) + 1;
    if (r.ok) latencies.push(r.ms);
    if (r.ok && r.status === 429 && first429 === null) first429 = r;
    if (r.ok && r.cf && firstCf === null) firstCf = r;
    if (!r.ok && firstErr === null) firstErr = r;
  }

  latencies.sort((a, b) => a - b);
  const p = (q) => latencies.length ? latencies[Math.min(latencies.length - 1, Math.floor(q * latencies.length))] : 0;

  log(`# Completed ${results.length} requests in ${elapsed}ms`);
  log(`# Status distribution: ${JSON.stringify(byStatus)}`);
  log(`# Latency (ok responses): p50=${p(0.5)}ms p90=${p(0.9)}ms max=${latencies[latencies.length - 1] || 0}ms`);

  if (first429) {
    log(`# RATE-LIMIT HIT: first HTTP 429 at request #${first429.idx} (~${first429.idx + 1} reqs in${first429.retryAfter ? `, Retry-After: ${first429.retryAfter}` : ""}).`);
  } else {
    log(`# No HTTP 429 observed in this burst.`);
  }
  if (firstCf) {
    log(`# CLOUDFLARE CHALLENGE/BLOCK: ${firstCf.cf} first at request #${firstCf.idx} (status ${firstCf.status}).`);
  } else {
    log(`# No Cloudflare challenge/block observed.`);
  }
  if (firstErr) {
    log(`# First network error at request #${firstErr.idx}: ${firstErr.err}`);
  }

  // Verdict
  if (first429 || firstCf) {
    log(`# VERDICT: rate-limiting / edge protection is ACTIVE (good — burst was throttled).`);
  } else {
    const errs = results.filter((r) => !r.ok).length;
    if (errs > TOTAL * 0.3) {
      log(`# VERDICT: ${errs}/${TOTAL} requests errored (connection-level throttling / drops — protection likely active but not clean 429).`);
    } else {
      log(`# VERDICT: burst of ${TOTAL} reqs/~3s passed WITHOUT a 429 or CF challenge — limit not tripped at this rate (note: nginx 25 r/s is per-IP and burst-tolerant; a single short burst near the limit may not trip it).`);
    }
  }

  mkdirSync(dirname(RESULTS), { recursive: true });
  appendFileSync(RESULTS, "\n" + lines.join("\n") + "\n");
  log("");
  log(`Appended to ${RESULTS}`);
}

run().catch((e) => {
  console.error("probe error:", e);
  process.exit(2);
});
