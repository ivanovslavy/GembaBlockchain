// Express app for the access-control backend. Wires validation + RLS-scoped DB +
// the on-chain AccessControlNFT. No PII ever goes on-chain (CLAUDE.md §10).
//
// Auth model (devnet): each request carries `x-tenant-id` (a tenant UUID); in
// production this comes from an authenticated API key -> tenant lookup. The tenant
// id drives RLS (db.withTenant), so an institution can only touch its own rows.

import express from 'express';
import { tenantRepo } from './db.js';
import { eraseEmployee } from './gdpr.js';
import { apiKeyAuth } from './auth.js';
import {
  ValidationError,
  requireUuid,
  requireEvmAddress,
  requireZone,
  requireNonEmptyString,
  optionalEmail,
} from './validation.js';

export function createApp({ pool, chain, apiKeys }) {
  const app = express();
  app.use(express.json());

  // Authentication: derive the tenant from the API key server-side — the client-supplied
  // x-tenant-id is NOT trusted (audit finding #1). RLS keys off this tenant id, so it must
  // come from an authenticated credential, never a header anyone can set.
  app.use(apiKeyAuth(apiKeys));

  const h = (fn) => (req, res, next) => fn(req, res, next).catch(next);

  // Register an employee (PII stays off-chain) and their wallet.
  app.post('/employees', h(async (req, res) => {
    const fullName = requireNonEmptyString('full_name', req.body.full_name);
    const email = optionalEmail('email', req.body.email);
    const wallet = requireEvmAddress('wallet', req.body.wallet);
    const created = await tenantRepo(pool, req.tenantId).createEmployee({ fullName, email, wallet });
    res.status(201).json(created);
  }));

  // Issue a capability: record off-chain mapping + mint the anonymous NFT on-chain.
  // The on-chain mint awaits a block (~seconds); it MUST NOT run inside an open DB
  // transaction (audit finding #1). So: read in a short tx, mint with no connection
  // held, then write in a second short tx.
  app.post('/capabilities', h(async (req, res) => {
    const employeeId = requireUuid('employee_id', req.body.employee_id);
    const zone = requireZone('zone', req.body.zone);
    const db = tenantRepo(pool, req.tenantId);
    const wallet = await db.getEmployeeWallet(employeeId); // short tx
    if (!wallet) throw new ValidationError('employee_id', 'unknown employee');
    const grantTx = await chain.grantAccess(wallet, zone); // no DB tx held
    const result = await db.createCapability({ employeeId, zone, grantTx }); // short tx
    res.status(201).json(result);
  }));

  // Record a physical-access event (off-chain only — never on-chain, §10).
  app.post('/access-logs', h(async (req, res) => {
    const employeeId = requireUuid('employee_id', req.body.employee_id);
    const zone = requireZone('zone', req.body.zone);
    if (typeof req.body.granted !== 'boolean') throw new ValidationError('granted', 'must be a boolean');
    await tenantRepo(pool, req.tenantId).logAccess({ employeeId, zone, granted: req.body.granted });
    res.status(201).json({ ok: true });
  }));

  // On-chain access check (anonymous: address + zone only).
  app.get('/access/:wallet/:zone', h(async (req, res) => {
    const wallet = requireEvmAddress('wallet', req.params.wallet);
    const zone = requireZone('zone', Number(req.params.zone));
    res.json({ wallet, zone, hasAccess: await chain.hasAccess(wallet, zone) });
  }));

  // GDPR right to erasure: revoke on-chain capabilities + delete off-chain PII.
  app.delete('/employees/:id', h(async (req, res) => {
    const employeeId = requireUuid('id', req.params.id);
    // tenantRepo runs each DB op in its own short tx; eraseEmployee deletes off-chain PII
    // FIRST, then best-effort revokes on-chain with no DB connection held (findings #1 + #2).
    const result = await eraseEmployee({ db: tenantRepo(pool, req.tenantId), chain }, employeeId);
    res.json(result);
  }));

  // Structured error handler — fail loud server-side, but never leak internals to clients.
  app.use((err, _req, res, _next) => {
    const status = err.status || 500;
    if (status >= 500) {
      // Don't return raw pg/RPC error text (which can include the RPC URL) to callers
      // (audit finding #12). Log the detail server-side, hand the client an opaque id.
      const id = Math.random().toString(36).slice(2, 10);
      console.error(`[error ${id}]`, err);
      return res.status(status).json({ error: 'InternalError', message: 'internal error', id });
    }
    res.status(status).json({ error: err.name || 'Error', message: err.message });
  });

  return app;
}
