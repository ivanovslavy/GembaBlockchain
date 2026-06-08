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

      byAddress.tryAcquire(to, now);
      byIp.tryAcquire(ip, now);
      try {
        const hash = await faucet.drip(to);
        res.json({ ok: true, to, amountGmb: DRIP_GMB, txHash: hash });
      } catch (sendErr) {
        // roll back the cooldown so a failed send doesn't burn the user's window
        byAddress.release(to);
        byIp.release(ip);
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
