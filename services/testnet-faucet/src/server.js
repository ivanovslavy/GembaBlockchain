// Testnet faucet HTTP service. POST /drip {address} sends test GMB, rate-limited
// per recipient address and per client IP. GET /health reports the faucet balance.
// Secrets (FAUCET_KEY) come from the environment, never committed (CLAUDE.md §3).

import express from 'express';
import { createFaucet } from './faucet.js';
import { isEvmAddress } from './validation.js';
import { CooldownLimiter } from './ratelimit.js';

const RPC_URL = process.env.TESTNET_EVM_RPC || 'http://localhost:8545';
const FAUCET_KEY = process.env.FAUCET_KEY; // testnet-only drip key
const DRIP_GMB = process.env.DRIP_AMOUNT_GMB || '100';
const COOLDOWN_MS = Number(process.env.DRIP_COOLDOWN_MS || 24 * 60 * 60 * 1000); // 24h
const PORT = process.env.FAUCET_PORT || 3002;

// FAUCET_CONTRACT set => MAINNET mode: drip via the on-chain GembaDripFaucet (on-chain
// per-address cooldown, restart-proof). Unset => testnet raw-send (off-chain limiter only).
const faucet = createFaucet({ rpcUrl: RPC_URL, faucetKey: FAUCET_KEY, dripAmountGmb: DRIP_GMB, faucetContract: process.env.FAUCET_CONTRACT });
const byAddress = new CooldownLimiter(COOLDOWN_MS);
const byIp = new CooldownLimiter(COOLDOWN_MS);

// Global drain protections (audit finding #7): the per-address cooldown is defeated by using a
// fresh recipient address per request, so add a daily GLOBAL budget and a min-balance circuit
// breaker on top.
const DAILY_GLOBAL_MAX = Number(process.env.DRIP_DAILY_GLOBAL_MAX || 10000); // max drips/day, all requesters
const MIN_BALANCE_WEI = BigInt(process.env.MIN_FAUCET_BALANCE_GMB || '1000') * 10n ** 18n; // refuse below this
let dripDay = 0;
let dripCountToday = 0;
function globalBudgetAllow(now) {
  const d = Math.floor(now / 86_400_000);
  if (d !== dripDay) {
    dripDay = d;
    dripCountToday = 0;
  }
  if (dripCountToday >= DAILY_GLOBAL_MAX) return false;
  dripCountToday++;
  return true;
}
function globalBudgetRelease() {
  if (dripCountToday > 0) dripCountToday--;
}

// Dependencies are injectable so the off-chain guard flow can be tested end-to-end with a
// mock faucet + fresh limiters (no real RPC). Production calls createApp() with no args.
export function createApp({ faucet: _faucet = faucet, byAddress: _byAddress = byAddress, byIp: _byIp = byIp } = {}) {
  const app = express();
  app.use(express.json());
  // Trust EXACTLY the number of reverse-proxy hops in front (default 1 = the documented
  // Apache front-end), so req.ip is the real upstream peer and a client cannot spoof its
  // rate-limit identity via a forged X-Forwarded-For header (audit finding #4). Run only
  // behind the reverse proxy.
  app.set('trust proxy', Number(process.env.TRUST_PROXY_HOPS || 1));

  app.get('/health', async (_req, res, next) => {
    try {
      res.json({ faucet: _faucet.address, balance: (await _faucet.balance()).toString(), dripGmb: DRIP_GMB });
    } catch (e) {
      next(e);
    }
  });

  app.post('/drip', async (req, res, next) => {
    try {
      const to = req.body?.address;
      if (!isEvmAddress(to)) return res.status(400).json({ error: 'address must be a 0x EVM address' });

      const ip = req.ip;
      const now = Date.now();

      // Acquire the cooldowns ATOMICALLY (honoring tryAcquire's return) BEFORE any await, so
      // concurrent same-address requests can't all pass a separate remaining() gate and then
      // drip — closing the TOCTOU race (audit L-3).
      if (!_byAddress.tryAcquire(to, now))
        return res.status(429).json({ error: 'address on cooldown', retryAfterMs: _byAddress.remaining(to, now) });
      if (!_byIp.tryAcquire(ip, now)) {
        _byAddress.release(to);
        return res.status(429).json({ error: 'ip on cooldown', retryAfterMs: _byIp.remaining(ip, now) });
      }
      // global daily budget (defends against the fresh-address bypass) + balance circuit breaker
      if (!globalBudgetAllow(now)) {
        _byAddress.release(to);
        _byIp.release(ip);
        return res.status(429).json({ error: 'global daily drip budget reached, try tomorrow' });
      }
      if ((await _faucet.balance()) < MIN_BALANCE_WEI) {
        _byAddress.release(to);
        _byIp.release(ip);
        globalBudgetRelease();
        return res.status(503).json({ error: 'faucet balance below floor; refill required' });
      }

      try {
        const hash = await _faucet.drip(to);
        res.json({ ok: true, to, amountGmb: DRIP_GMB, txHash: hash });
      } catch (sendErr) {
        // roll back the cooldown + global budget so a failed send doesn't burn the window/budget
        _byAddress.release(to);
        _byIp.release(ip);
        globalBudgetRelease();
        throw sendErr;
      }
    } catch (e) {
      next(e);
    }
  });

  app.use((err, _req, res, _next) => {
    // Don't leak internal error text (ethers/RPC errors include the configured RPC URL)
    // to clients (audit finding #12). Log the detail server-side, return an opaque id.
    const id = Math.random().toString(36).slice(2, 10);
    console.error(`[faucet error ${id}]`, err);
    res.status(500).json({ error: 'internal error', id });
  });

  return app;
}

// MAINNET guard (owner decision 2026-07-17): the small 0.1 GMB/day public faucet DOES run
// on mainnet, but ONLY in contract mode (FAUCET_CONTRACT -> on-chain GembaDripFaucet with
// its on-chain cooldown). The testnet raw-send mode holds a hot key that drips unlimited
// amounts on operator error — refuse to start it against the mainnet chain.
const MAINNET_EVM_CHAIN_ID = 821206n;
export async function assertNotRawModeOnMainnet({ rpcUrl = RPC_URL, faucetContract = process.env.FAUCET_CONTRACT } = {}) {
  if (faucetContract) return; // contract mode — allowed everywhere
  const { ethers } = await import('ethers');
  const { chainId } = await new ethers.JsonRpcProvider(rpcUrl).getNetwork();
  if (chainId === MAINNET_EVM_CHAIN_ID) {
    throw new Error(
      `refusing to start: raw-send faucet mode on MAINNET (chainId ${chainId}). ` +
        'Set FAUCET_CONTRACT to the GembaDripFaucet address (contract mode is the only mainnet mode).'
    );
  }
}

if (process.env.NODE_ENV !== 'test') {
  assertNotRawModeOnMainnet()
    .then(() => createApp().listen(PORT, () => console.log(`testnet faucet on :${PORT} (drip ${DRIP_GMB} GMB)`)))
    .catch((e) => {
      console.error(String(e?.message || e));
      process.exit(1);
    });
}
