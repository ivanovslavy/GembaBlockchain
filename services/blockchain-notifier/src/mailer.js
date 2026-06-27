// Email delivery + dedup. Email-ONLY (no Telegram, by design). Every message is unmistakably
// labelled TESTNET / MAINNET in the subject AND the first body line (with the chain-id), so the
// two environments can never be confused once both run.
import nodemailer from 'nodemailer';
import { cfg } from './config.js';

let transport = null;
function getTransport() {
  if (!cfg.smtp.host) return null;
  if (!transport) {
    transport = nodemailer.createTransport({
      host: cfg.smtp.host,
      port: cfg.smtp.port,
      secure: cfg.smtp.port === 465,
      auth: cfg.smtp.user ? { user: cfg.smtp.user, pass: cfg.smtp.pass } : undefined,
    });
  }
  return transport;
}

// in-memory dedup so a still-true condition doesn't email every poll; re-notify after cooldown
const lastSent = new Map();
const COOLDOWN_MS = Number(process.env.ALERT_COOLDOWN_MS || 3 * 60 * 60 * 1000); // 3h

/**
 * Send a notification email. `key` dedups repeats; `level` ∈ info|warning|critical.
 * Returns true if sent (or dry-run logged), false if suppressed by cooldown.
 */
export async function notify(key, subject, body, level = 'info') {
  const now = Date.now();
  const prev = lastSent.get(key);
  if (prev && now - prev < COOLDOWN_MS) return false;
  lastSent.set(key, now);

  const subj = `[GembaChain · ${cfg.LABEL} · ${level}] ${subject}`;
  const text =
    `Network: GembaBlockchain ${cfg.LABEL} — ${cfg.cosmosChainId} / EVM chainId ${cfg.chainId}\n` +
    `Severity: ${level}\n` +
    `Time: ${new Date().toISOString()}\n` +
    `Explorer: ${cfg.explorer}\n` +
    `\n${body}\n`;

  const t = getTransport();
  if (!t || cfg.dryRun) {
    console.log(`\n──── [DRY-RUN EMAIL] ────\nFrom: ${cfg.smtp.from}\nTo:   ${cfg.smtp.to}\nSubj: ${subj}\n${text}────────────────────────\n`);
    return true;
  }
  await t.sendMail({ from: cfg.smtp.from, to: cfg.smtp.to, subject: subj, text });
  console.log(`[email sent] ${subj}`);
  return true;
}

/** clear a dedup key so the NEXT occurrence emails immediately (e.g. a service recovered). */
export function resetKey(key) {
  lastSent.delete(key);
}
