// gembachain.io contact-form backend: verifies Cloudflare Turnstile, emails the inquiry to
// contacts@ and a confirmation copy to the sender. Sends as noreply@ (auth = sender, so the
// mail server accepts the From). Mounted behind Apache at gembachain.io/api/contact.
import 'dotenv/config';
import express from 'express';
import nodemailer from 'nodemailer';

const PORT = Number(process.env.PORT || 3115);
const TURNSTILE_SECRET = process.env.TURNSTILE_SECRET || '';
const CONTACT_TO = process.env.CONTACT_EMAIL || 'contacts@gembachain.io';

const transport = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT || 587),
  secure: String(process.env.SMTP_SECURE) === 'true',
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
});
const FROM = `"${process.env.SMTP_FROM_NAME || 'GembaBlockchain'}" <${process.env.SMTP_FROM_EMAIL || process.env.SMTP_USER}>`;

const app = express();
app.use(express.json({ limit: '32kb' }));

const clean = (s, max) => String(s ?? '').trim().slice(0, max);
const isEmail = (s) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);

async function verifyTurnstile(token, ip) {
  if (!TURNSTILE_SECRET) return false;
  const body = new URLSearchParams({ secret: TURNSTILE_SECRET, response: token });
  if (ip) body.append('remoteip', ip);
  const r = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST', body, signal: AbortSignal.timeout(8000),
  });
  const j = await r.json();
  return !!j.success;
}

app.get('/api/contact/health', (_req, res) => res.json({ ok: true }));

app.post('/api/contact', async (req, res) => {
  try {
    const name = clean(req.body.name, 120);
    const email = clean(req.body.email, 160);
    const subject = clean(req.body.subject, 160) || 'Contact form message';
    const message = clean(req.body.message, 5000);
    const token = clean(req.body.token || req.body['cf-turnstile-response'], 4096);

    if (!name || !isEmail(email) || !message) return res.status(400).json({ ok: false, error: 'invalid_input' });

    const ip = (req.headers['cf-connecting-ip'] || req.headers['x-forwarded-for'] || '').toString().split(',')[0].trim();
    if (!(await verifyTurnstile(token, ip))) return res.status(403).json({ ok: false, error: 'turnstile_failed' });

    // 1) inquiry → contacts@  (reply-to the sender so you can answer directly)
    await transport.sendMail({
      from: FROM, to: CONTACT_TO, replyTo: `${name} <${email}>`,
      subject: `[gembachain.io] ${subject}`,
      text: `New contact-form message from gembachain.io\n\nName: ${name}\nEmail: ${email}\nSubject: ${subject}\n\n${message}\n`,
    });

    // 2) confirmation copy → the sender
    await transport.sendMail({
      from: FROM, to: email,
      subject: 'We received your message — GembaBlockchain',
      text: `Hi ${name},\n\nThanks for reaching out to GembaBlockchain — we received your message and will get back to you soon.\n\nYour message:\n"${message}"\n\n— The GembaBlockchain team\nhttps://gembachain.io`,
    });

    res.json({ ok: true });
  } catch (e) {
    console.error('[contact]', e?.message || e);
    res.status(500).json({ ok: false, error: 'send_failed' });
  }
});

app.listen(PORT, '127.0.0.1', () => console.log(`contact-form listening on 127.0.0.1:${PORT}`));
