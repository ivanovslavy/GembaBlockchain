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

const faucet = createFaucet({ rpcUrl: RPC_URL, faucetKey: FAUCET_KEY, dripAmountGmb: DRIP_GMB });
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

export function createApp() {
  const app = express();
  app.use(express.json());
  // Trust EXACTLY the number of reverse-proxy hops in front (default 1 = the documented
  // Apache front-end), so req.ip is the real upstream peer and a client cannot spoof its
  // rate-limit identity via a forged X-Forwarded-For header (audit finding #4). Run only
  // behind the reverse proxy.
  app.set('trust proxy', Number(process.env.TRUST_PROXY_HOPS || 1));

  app.get('/health', async (_req, res, next) => {
    try {
      res.json({ faucet: faucet.address, balance: (await faucet.balance()).toString(), dripGmb: DRIP_GMB });
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
      if (byAddress.remaining(to, now) > 0)
        return res.status(429).json({ error: 'address on cooldown', retryAfterMs: byAddress.remaining(to, now) });
      if (byIp.remaining(ip, now) > 0)
        return res.status(429).json({ error: 'ip on cooldown', retryAfterMs: byIp.remaining(ip, now) });

      // global daily budget (defends against the fresh-address bypass) + balance circuit breaker
      if (!globalBudgetAllow(now))
        return res.status(429).json({ error: 'global daily drip budget reached, try tomorrow' });
      if ((await faucet.balance()) < MIN_BALANCE_WEI) {
        globalBudgetRelease();
        return res.status(503).json({ error: 'faucet balance below floor; refill required' });
      }

      byAddress.tryAcquire(to, now);
      byIp.tryAcquire(ip, now);
      try {
        const hash = await faucet.drip(to);
        res.json({ ok: true, to, amountGmb: DRIP_GMB, txHash: hash });
      } catch (sendErr) {
        // roll back the cooldown + global budget so a failed send doesn't burn the window/budget
        byAddress.release(to);
        byIp.release(ip);
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

if (process.env.NODE_ENV !== 'test') {
  createApp().listen(PORT, () => console.log(`testnet faucet on :${PORT} (drip ${DRIP_GMB} GMB)`));
}
