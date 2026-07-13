// GembaBlockchain GMB purchase backend.
// Flow: customer enters an EVM address + GMB amount on gembachain.io → POST /create → we make a
// GembaPay payment-request (our own orderId) and return its hosted checkout URL → customer pays →
// GembaPay POSTs a SIGNED `payment.completed` webhook → we verify the HMAC, look up the order,
// and call dispense(evmAddress, gmbAmount, ref) on the GembaPayDispenser so GMB reaches the buyer.
// The dispense happens ONLY after the webhook confirms payment (CLAUDE.md: never before).
import 'dotenv/config';
import express from 'express';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { JsonRpcProvider, Wallet, Contract, isAddress, parseEther, id as keccakId } from 'ethers';

const cfg = {
  port: Number(process.env.PORT || 3116),
  gembapayApi: process.env.GEMBAPAY_API_BASE || 'https://api.gembapay.com',
  gembapayKey: process.env.GEMBAPAY_API_KEY || '',
  whsec: process.env.GEMBAPAY_WEBHOOK_SECRET || '',
  checkoutBase: process.env.GEMBAPAY_CHECKOUT_BASE || 'https://payment.gembapay.com',
  pricePerGmbEur: Number(process.env.GMB_PRICE_EUR || 0.10),
  minGmb: Number(process.env.MIN_GMB || 10),
  maxGmb: Number(process.env.MAX_GMB || 10000),
  rpc: process.env.GEMBA_RPC_URL || 'https://rpc1.gembascan.io',
  chainId: Number(process.env.GEMBA_CHAIN_ID || 821207),
  dispenser: process.env.GEMBA_DISPENSER_ADDRESS || '',
  ownerPk: process.env.GEMBA_DISPENSER_OWNER_PK || '',
  store: process.env.STORE_FILE || path.join(process.cwd(), 'data', 'orders.json'),
};

// ---- tiny JSON order store: orderId -> {evmAddress, gmbAmount, eur, status, txHash, ts} ----
function load() { try { return JSON.parse(fs.readFileSync(cfg.store, 'utf8')); } catch { return {}; } }
function save(s) { fs.mkdirSync(path.dirname(cfg.store), { recursive: true }); fs.writeFileSync(cfg.store, JSON.stringify(s, null, 2)); }
let orders = load();
const inflight = new Set(); // orderIds being dispensed (dedup concurrent webhooks)

// ---- chain ----
const provider = new JsonRpcProvider(cfg.rpc, cfg.chainId, { staticNetwork: true });
const signer = cfg.ownerPk ? new Wallet(cfg.ownerPk, provider) : null;
const DISPENSER_ABI = ['function dispense(address to, uint256 amount, bytes32 ref) external'];
const dispenser = signer ? new Contract(cfg.dispenser, DISPENSER_ABI, signer) : null;

async function dispenseGmb(orderId, to, gmbAmount) {
  const ref = keccakId(orderId); // bytes32 = keccak256(orderId)
  const tx = await dispenser.dispense(to, parseEther(String(gmbAmount)), ref, { gasLimit: 120000 });
  const rec = await tx.wait(1);
  return rec?.hash || tx.hash;
}

const app = express();

app.get('/api/purchase/health', (_req, res) => res.json({ ok: true }));

// pricing/config for the frontend
app.get('/api/purchase/config', (_req, res) =>
  res.json({ pricePerGmbEur: cfg.pricePerGmbEur, minGmb: cfg.minGmb, maxGmb: cfg.maxGmb, chainId: cfg.chainId, dispenser: cfg.dispenser }));

// 1) create a purchase → GembaPay payment-request → hosted checkout URL
app.post('/api/purchase/create', express.json({ limit: '8kb' }), async (req, res) => {
  try {
    const evmAddress = String(req.body.evmAddress || '').trim();
    const gmb = Number(req.body.gmbAmount);
    if (!isAddress(evmAddress)) return res.status(400).json({ ok: false, error: 'invalid_evm_address' });
    if (!(gmb >= cfg.minGmb && gmb <= cfg.maxGmb)) return res.status(400).json({ ok: false, error: 'invalid_amount' });

    const eur = Math.round(gmb * cfg.pricePerGmbEur * 100) / 100;
    const orderId = 'gmb_' + crypto.randomBytes(12).toString('hex');
    orders[orderId] = { evmAddress, gmbAmount: gmb, eur, status: 'pending', ts: Date.now() };
    save(orders);

    const r = await fetch(`${cfg.gembapayApi}/api/merchant/payment-request`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${cfg.gembapayKey}` },
      body: JSON.stringify({ orderId, amount: eur, currency: 'EUR', description: `${gmb} GMB → ${evmAddress}` }),
      signal: AbortSignal.timeout(15000),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) { console.error('[create] gembapay', r.status, j); return res.status(502).json({ ok: false, error: 'gateway_error' }); }
    const checkoutUrl = j.paymentUrl || `${cfg.checkoutBase}/checkout/${orderId}`;
    res.json({ ok: true, orderId, checkoutUrl, eur, gmb });
  } catch (e) {
    console.error('[create]', e?.message || e);
    res.status(500).json({ ok: false, error: 'create_failed' });
  }
});

// 2) GembaPay webhook (signed) → dispense after payment is confirmed
app.post('/api/purchase/webhook', express.raw({ type: '*/*', limit: '64kb' }), async (req, res) => {
  try {
    const sig = String(req.headers['x-gembapay-signature'] || '');
    const raw = req.body instanceof Buffer ? req.body : Buffer.from('');
    const expected = crypto.createHmac('sha256', cfg.whsec).update(raw).digest('hex');
    const ok = sig.length === expected.length && crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
    if (!ok) { console.warn('[webhook] bad signature'); return res.status(401).json({ ok: false }); }

    const body = JSON.parse(raw.toString('utf8'));
    const event = body.event || req.headers['x-gembapay-event'];
    const p = body.payment || {};
    // The GembaPay webhook signals completion via the top-level `event`; the payment object
    // does NOT carry a `status` field, so don't require p.status (that silently ignored every
    // payment.completed webhook → GMB never dispensed).
    if (event !== 'payment.completed') return res.json({ ok: true, ignored: true });

    const orderId = p.orderId;
    const o = orders[orderId];
    if (!o) { console.warn('[webhook] unknown order', orderId); return res.json({ ok: true, unknown: true }); }
    if (o.status === 'fulfilled' || inflight.has(orderId)) return res.json({ ok: true, already: true }); // idempotent

    // Defense-in-depth (SEC audit H2): the HMAC authenticates the body, but also cross-check the
    // paid amount + currency against the stored order so a `payment.completed` for a different or
    // partial amount can't dispense the full GMB. Lenient: only enforce fields the webhook carries.
    const paidCcy = String(p.currency || body.currency || '').toUpperCase();
    const paidAmt = Number(p.amount ?? body.amount);
    if (paidCcy && paidCcy !== 'EUR') { console.warn('[webhook] currency mismatch', paidCcy, orderId); return res.status(400).json({ ok: false, error: 'currency_mismatch' }); }
    if (Number.isFinite(paidAmt) && Math.abs(paidAmt - o.eur) > 0.01) { console.warn('[webhook] amount mismatch', paidAmt, o.eur, orderId); return res.status(400).json({ ok: false, error: 'amount_mismatch' }); }

    inflight.add(orderId);
    try {
      const hash = await dispenseGmb(orderId, o.evmAddress, o.gmbAmount);
      o.status = 'fulfilled'; o.txHash = hash; o.fulfilledAt = Date.now(); save(orders);
      console.log(`[webhook] dispensed ${o.gmbAmount} GMB -> ${o.evmAddress} (order ${orderId}) tx ${hash}`);
    } finally { inflight.delete(orderId); }
    res.json({ ok: true });
  } catch (e) {
    console.error('[webhook]', e?.message || e);
    res.status(500).json({ ok: false });
  }
});

// 3) status (the page polls this after the customer returns)
app.get('/api/purchase/status/:orderId', (req, res) => {
  const o = orders[req.params.orderId];
  if (!o) return res.status(404).json({ ok: false });
  res.json({ ok: true, status: o.status, gmb: o.gmbAmount, evmAddress: o.evmAddress, txHash: o.txHash || null });
});

// Fail CLOSED on missing security config (SEC audit H2). An empty GEMBAPAY_WEBHOOK_SECRET makes
// the webhook HMAC keyed on "" — anyone could forge `payment.completed` and mint GMB via dispense.
// Likewise a missing dispenser signer/address means we cannot safely operate. Refuse to start.
if (!cfg.whsec) {
  console.error('FATAL: GEMBAPAY_WEBHOOK_SECRET is empty — refusing to start (webhook auth would be forgeable → arbitrary GMB dispense).');
  process.exit(1);
}
if (!signer || !cfg.dispenser) {
  console.error('FATAL: GEMBA_DISPENSER_OWNER_PK / GEMBA_DISPENSER_ADDRESS missing — refusing to start.');
  process.exit(1);
}

app.listen(cfg.port, '127.0.0.1', () => {
  console.log(`purchase-backend on 127.0.0.1:${cfg.port} | dispenser=${cfg.dispenser} | price=${cfg.pricePerGmbEur} EUR/GMB | signer=${signer ? 'set' : 'MISSING'}`);
});
