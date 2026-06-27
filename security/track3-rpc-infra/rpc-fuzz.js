#!/usr/bin/env node
// Track 3 — JSON-RPC fuzzing harness (NON-DESTRUCTIVE, bad-input only, MODEST volume).
//
// Sends malformed / abusive JSON-RPC to the 3 public endpoints and checks each
// returns a *graceful* JSON error and keeps the connection alive — no crash, no 5xx
// storm, no hang, no stack-trace / internal-detail leak. This is a robustness probe,
// NOT a DoS: a few dozen sequential requests per endpoint with small delays.
//
// Run: node security/track3-rpc-infra/rpc-fuzz.js
// Writes a summary to security/results/rpc-fuzz.txt
//
// See docs/security-pentest-2026-06-24.md (Track 3).

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const RESULTS = join(__dirname, "..", "results", "rpc-fuzz.txt");

const ENDPOINTS = [
  // post-regenesis: one public RPC per Contabo validator (the old testnet.gembascan.io/rpc
  // archive endpoint is gone — 410). All three fuzzed.
  { name: "rpc1", url: "https://rpc1.gembascan.io" },
  { name: "rpc2", url: "https://rpc2.gembascan.io" },
  { name: "rpc3", url: "https://rpc3.gembascan.io" },
];

const REQ_TIMEOUT_MS = 10_000; // anything >10s counts as a "hang"
const CASE_DELAY_MS = 250; // be polite — sequential, throttled
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- Fuzz cases. Each returns a raw request body (string) to POST. ----
// Some need a "latest" block number; resolved at runtime per endpoint.
function buildCases(latestHex) {
  const bigInt = "0x" + "f".repeat(100_000); // ~100k-char hex param

  // deeply nested array param, ~1000 deep: [[[...]]]
  const depth = 1000;
  const nested = "[".repeat(depth) + "0" + "]".repeat(depth);

  // batch of ~50 mixed calls (valid + a few invalid)
  const batch = [];
  for (let i = 0; i < 50; i++) {
    if (i % 10 === 0) batch.push({ jsonrpc: "2.0", id: i, method: "no_such_method_" + i, params: [] });
    else if (i % 7 === 0) batch.push({ jsonrpc: "2.0", id: i, method: "eth_getBalance", params: [12345, "latest"] });
    else batch.push({ jsonrpc: "2.0", id: i, method: "eth_blockNumber", params: [] });
  }

  return [
    {
      case: "invalid-json",
      // not valid JSON at all
      body: '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber" PARAMS-BROKEN',
      expect: "json-rpc-error", // want -32700 parse error
    },
    {
      case: "missing-jsonrpc-field",
      body: JSON.stringify({ id: 1, method: "eth_blockNumber", params: [] }),
      expect: "any-graceful", // either error or tolerant result, just not a crash
    },
    {
      case: "missing-id",
      body: JSON.stringify({ jsonrpc: "2.0", method: "eth_blockNumber", params: [] }),
      expect: "any-graceful",
    },
    {
      case: "unknown-method",
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "totally_made_up_method", params: [] }),
      expect: "json-rpc-error", // want -32601 method not found
    },
    {
      case: "wrong-param-type (getBalance int addr)",
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_getBalance", params: [12345, "latest"] }),
      expect: "json-rpc-error", // want -32602 invalid params
    },
    {
      case: "oversized-hex-param (~100k chars)",
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_getBalance", params: [bigInt, "latest"] }),
      expect: "any-graceful",
    },
    {
      case: "deeply-nested-params (~1000 deep)",
      body: `{"jsonrpc":"2.0","id":1,"method":"eth_getBalance","params":${nested}}`,
      expect: "any-graceful",
    },
    {
      case: "batch-50-mixed",
      body: JSON.stringify(batch),
      expect: "batch-array", // want a JSON array back, no crash
    },
    {
      case: "eth_getLogs full-range (0..latest)",
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "eth_getLogs",
        params: [{ fromBlock: "0x0", toBlock: latestHex || "latest" }],
      }),
      expect: "any-graceful", // node may bound the range and reject — that's a PASS
    },
    {
      case: "huge eth_call data (~100k hex)",
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "eth_call",
        params: [{ to: "0x0000000000000000000000000000000000000000", data: bigInt }, "latest"],
      }),
      expect: "any-graceful",
    },
  ];
}

// crude stack-trace / internal-detail sniffing on the response text
const LEAK_PATTERNS = [
  /goroutine\s/i,
  /\bpanic:/i,
  /runtime error/i,
  /\.go:\d+/, // Go source path:line
  /\/home\/[a-z]/i, // server filesystem path
  /\/root\//i,
  /github\.com\/cosmos/i,
  /\bnginx\b.*\d+\.\d+\.\d+/i, // nginx version banner
  /Traceback \(most recent/i,
];

function sniffLeak(text) {
  if (!text) return null;
  for (const re of LEAK_PATTERNS) if (re.test(text)) return re.toString();
  return null;
}

function classify(expect, status, parsed, isArray, rawText) {
  // Returns { ok: bool, note: string }
  const leak = sniffLeak(rawText);
  if (status >= 500) return { ok: false, note: `5xx (${status})` };
  if (leak) return { ok: false, note: `INTERNAL-DETAIL LEAK: ${leak}` };

  // A JSON-RPC *notification* (request with no `id`) MUST get no response body
  // per the spec — an empty 2xx body is the CORRECT, graceful behaviour.
  if (expect === "any-graceful" && status >= 200 && status < 300 && (rawText || "").trim() === "") {
    return { ok: true, note: "empty body (notification — spec-correct)" };
  }

  if (expect === "batch-array") {
    if (isArray) return { ok: true, note: `array len=${parsed.length}` };
    if (parsed && parsed.error) return { ok: true, note: `single json-rpc error (acceptable)` };
    return { ok: false, note: "batch did not return array or error" };
  }
  if (expect === "json-rpc-error") {
    if (parsed && parsed.error && typeof parsed.error.code === "number")
      return { ok: true, note: `error code ${parsed.error.code}` };
    if (parsed && "result" in parsed)
      return { ok: true, note: "tolerant result (no crash)" }; // graceful, just lenient
    return { ok: false, note: "no json-rpc error object" };
  }
  // any-graceful: any well-formed JSON-RPC envelope (result or error) is a PASS
  if (parsed && (("result" in parsed) || parsed.error)) {
    return { ok: true, note: parsed.error ? `error code ${parsed.error?.code}` : "result" };
  }
  if (isArray) return { ok: true, note: `array len=${parsed.length}` };
  return { ok: false, note: "unexpected (no valid json-rpc envelope)" };
}

async function post(url, body) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), REQ_TIMEOUT_MS);
  const started = Date.now();
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      signal: ctrl.signal,
    });
    const text = await res.text();
    return { status: res.status, text, ms: Date.now() - started, hung: false, dropped: false };
  } catch (e) {
    const ms = Date.now() - started;
    const hung = e.name === "AbortError";
    // network-level drop (connection reset / DNS / TLS) vs timeout
    return { status: 0, text: "", ms, hung, dropped: !hung, err: e.message };
  } finally {
    clearTimeout(t);
  }
}

async function getLatestHex(url) {
  try {
    const r = await post(url, JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_blockNumber", params: [] }));
    const j = JSON.parse(r.text);
    return j.result;
  } catch {
    return null;
  }
}

const lines = [];
const log = (s) => {
  lines.push(s);
  console.log(s);
};

async function run() {
  log(`# Track 3 — JSON-RPC fuzzing harness`);
  log(`# Run: ${new Date().toISOString()}`);
  log(`# Non-destructive, bad-input only, sequential, ${CASE_DELAY_MS}ms between cases.`);
  log("");

  const flags = []; // anything that needs a human's attention

  for (const ep of ENDPOINTS) {
    log(`──────── ${ep.name}  (${ep.url}) ────────`);
    const latestHex = await getLatestHex(ep.url);
    const cases = buildCases(latestHex);

    for (const c of cases) {
      const r = await post(ep.url, c.body);

      let parsed = null;
      let isArray = false;
      try {
        parsed = JSON.parse(r.text);
        isArray = Array.isArray(parsed);
      } catch {
        parsed = null;
      }

      let verdict;
      if (r.hung) verdict = { ok: false, note: `HANG >${REQ_TIMEOUT_MS}ms` };
      else if (r.dropped) verdict = { ok: false, note: `CONNECTION DROPPED (${r.err})` };
      else verdict = classify(c.expect, r.status, parsed, isArray, r.text);

      const tag = verdict.ok ? "PASS" : "FLAG";
      const line = `  [${tag}] ${ep.name.padEnd(7)} | ${c.case.padEnd(34)} | HTTP ${String(r.status).padEnd(3)} | ${String(r.ms).padStart(5)}ms | ${verdict.note}`;
      log(line);

      if (!verdict.ok) {
        const snippet = (r.text || r.err || "").slice(0, 300).replace(/\s+/g, " ");
        flags.push(`${ep.name} / ${c.case}: ${verdict.note} :: ${snippet}`);
      }

      await sleep(CASE_DELAY_MS);
    }
    log("");
  }

  log("──────── SUMMARY ────────");
  if (flags.length === 0) {
    log("  All cases returned a graceful JSON-RPC envelope (or a bounded rejection).");
    log("  No 5xx, no dropped connections, no hangs, no internal-detail leaks observed.");
  } else {
    log(`  ${flags.length} case(s) FLAGGED for review:`);
    for (const f of flags) log(`    - ${f}`);
  }

  mkdirSync(dirname(RESULTS), { recursive: true });
  writeFileSync(RESULTS, lines.join("\n") + "\n");
  log("");
  log(`Wrote ${RESULTS}`);

  // non-zero exit if anything flagged, so CI can gate on it
  process.exit(flags.length === 0 ? 0 : 1);
}

run().catch((e) => {
  console.error("harness error:", e);
  process.exit(2);
});
