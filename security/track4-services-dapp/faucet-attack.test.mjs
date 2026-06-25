// Track 4 — testnet-faucet adversarial tests. Run: node --test security/track4-services-dapp/faucet-attack.test.mjs
// Demonstrates the *bounds* of the faucet's rate-limiting under active attack. These
// are accepted/known findings (#7, #11); the tests pin the exact attacker capability
// so the operator can decide mitigations. See docs/security-pentest-2026-06-24.md.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CooldownLimiter } from '../../services/testnet-faucet/src/ratelimit.js';

const DAY = 24 * 3600 * 1000;

// ATTACK 1 — Sybil: the per-ADDRESS cooldown is per-key, so unlimited fresh wallets
// each look "new". A scripted attacker drips to N fresh addresses with zero wait;
// only the server's GLOBAL daily budget (not this limiter) bounds the bleed.
test('ATTACK: fresh addresses defeat the per-address cooldown (sybil)', () => {
  const perAddr = new CooldownLimiter(DAY);
  const now = 1_000_000;
  let drips = 0;
  for (let i = 0; i < 10_000; i++) {
    const freshAddr = '0x' + i.toString(16).padStart(40, '0');
    if (perAddr.tryAcquire(freshAddr, now)) drips++; // same instant, all succeed
  }
  assert.equal(drips, 10_000, 'every fresh address bypasses the address cooldown');
  // the SAME address is correctly blocked within the window:
  assert.equal(perAddr.tryAcquire('0x' + '0'.repeat(40), now + 1), false);
  // => Only DRIP_DAILY_GLOBAL_MAX + the MIN_BALANCE circuit breaker bound the drain.
});

// ATTACK 2 — Restart resets all cooldowns (finding #11): the limiter is an in-process
// Map. A process restart (crash, deploy, OOM) wipes every cooldown, so an address
// that just drank can drink again immediately on the new process.
test('ATTACK: process restart wipes cooldowns (in-memory only)', () => {
  const addr = '0xabc' + '0'.repeat(37);
  let lim = new CooldownLimiter(DAY);
  const now = 5_000_000;
  assert.equal(lim.tryAcquire(addr, now), true);
  assert.equal(lim.tryAcquire(addr, now + 1000), false, 'blocked within window');
  // simulate restart: a fresh limiter (no shared/persistent store)
  lim = new CooldownLimiter(DAY);
  assert.equal(lim.tryAcquire(addr, now + 1000), true, 'cooldown lost across restart');
  // => Mitigation: back the limiter with a shared TTL store (Redis) for restart/multi-instance durability.
});

// ATTACK 3 — Per-IP cooldown only helps if req.ip is trustworthy. With a misconfigured
// trust-proxy an attacker spoofs X-Forwarded-For to mint a new key per request. (The
// code sets trust proxy = 1; this asserts the limiter itself keys purely on the value
// it is given — the protection lives entirely in deriving req.ip correctly upstream.)
test('ATTACK: per-IP limiter is only as strong as the derived client IP', () => {
  const perIp = new CooldownLimiter(DAY);
  const now = 9_000_000;
  let ok = 0;
  for (let i = 0; i < 1000; i++) if (perIp.tryAcquire('203.0.113.' + i, now)) ok++; // spoofed XFF -> new IP each time
  assert.equal(ok, 1000, 'spoofable client IP => per-IP cooldown bypassed');
});

// CONTEXT (P-1): all of the above is the SERVICE rate-limiting. Because the live
// faucet account's private key is derivable from a repo-hardcoded mnemonic (finding
// P-1, 0x40a0cb1C...eFa9), an attacker bypasses this service ENTIRELY — signing a
// direct transfer with the recovered key drains the faucet in one tx, ignoring every
// limit above. Rotating the key (P-1 fix) is the prerequisite for any of this rate-
// limiting to matter. This is asserted as documentation, not code:
test('CONTEXT: service rate-limiting is moot while the faucet key is public (P-1)', () => {
  const faucetKeyIsPublic = true; // P-1: derivable from chain/scripts/init-multinode.sh
  assert.ok(faucetKeyIsPublic, 'rotate the faucet key (P-1) before relying on rate limits');
});
