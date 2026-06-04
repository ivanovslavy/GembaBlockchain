// Express app for the access-control backend. Wires validation + RLS-scoped DB +
// the on-chain AccessControlNFT. No PII ever goes on-chain (CLAUDE.md §10).
//
// Auth model (devnet): each request carries `x-tenant-id` (a tenant UUID); in
// production this comes from an authenticated API key -> tenant lookup. The tenant
// id drives RLS (db.withTenant), so an institution can only touch its own rows.

import express from 'express';
import { withTenant } from './db.js';
import { eraseEmployee } from './gdpr.js';
import {
  ValidationError,
  requireUuid,
  requireEvmAddress,
  requireZone,
  requireNonEmptyString,
  optionalEmail,
} from './validation.js';

export function createApp({ pool, chain }) {
  const app = express();
  app.use(express.json());

  // Tenant context (drives RLS). Fail loud if missing/malformed.
  app.use((req, _res, next) => {
    try {
      req.tenantId = requireUuid('x-tenant-id', req.header('x-tenant-id'));
      next();
    } catch (err) {
      next(err);
    }
  });

  const h = (fn) => (req, res, next) => fn(req, res, next).catch(next);

  // Register an employee (PII stays off-chain) and their wallet.
  app.post('/employees', h(async (req, res) => {
    const fullName = requireNonEmptyString('full_name', req.body.full_name);
    const email = optionalEmail('email', req.body.email);
    const wallet = requireEvmAddress('wallet', req.body.wallet);
    const created = await withTenant(pool, req.tenantId, (db) =>
      db.createEmployee({ fullName, email, wallet })
    );
    res.status(201).json(created);
  }));

  // Issue a capability: record off-chain mapping + mint the anonymous NFT on-chain.
  app.post('/capabilities', h(async (req, res) => {
    const employeeId = requireUuid('employee_id', req.body.employee_id);
    const zone = requireZone('zone', req.body.zone);
    const result = await withTenant(pool, req.tenantId, async (db) => {
      const wallet = await db.getEmployeeWallet(employeeId);
      if (!wallet) throw new ValidationError('employee_id', 'unknown employee');
      const grantTx = await chain.grantAccess(wallet, zone); // on-chain mint
      return db.createCapability({ employeeId, zone, grantTx });
    });
    res.status(201).json(result);
  }));

  // Record a physical-access event (off-chain only — never on-chain, §10).
  app.post('/access-logs', h(async (req, res) => {
    const employeeId = requireUuid('employee_id', req.body.employee_id);
    const zone = requireZone('zone', req.body.zone);
    if (typeof req.body.granted !== 'boolean') throw new ValidationError('granted', 'must be a boolean');
    await withTenant(pool, req.tenantId, (db) =>
      db.logAccess({ employeeId, zone, granted: req.body.granted })
    );
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
    const result = await withTenant(pool, req.tenantId, (db) =>
      eraseEmployee({ db, chain }, employeeId)
    );
    res.json(result);
  }));

  // Structured error handler — fail loud, never silent.
  app.use((err, _req, res, _next) => {
    const status = err.status || 500;
    res.status(status).json({ error: err.name || 'Error', message: err.message });
  });

  return app;
}
