import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseApiKeys, apiKeyAuth } from '../src/auth.js';

test('parseApiKeys parses key:tenant pairs', () => {
  const m = parseApiKeys('k1:t1, k2:t2');
  assert.equal(m.get('k1'), 't1');
  assert.equal(m.get('k2'), 't2');
  assert.equal(m.size, 2);
});

function run(mw, headers) {
  const req = { header: (h) => headers[h.toLowerCase()] };
  let status = 200, body = null, nexted = false;
  const res = { status(c) { status = c; return this; }, json(b) { body = b; return this; } };
  mw(req, res, () => { nexted = true; });
  return { req, status, body, nexted };
}

test('apiKeyAuth derives tenant from the key and ignores x-tenant-id (finding #1)', () => {
  const mw = apiKeyAuth(parseApiKeys('secret:tenant-1'));

  let r = run(mw, { 'x-api-key': 'secret' });
  assert.equal(r.nexted, true);
  assert.equal(r.req.tenantId, 'tenant-1');

  // a spoofed x-tenant-id must be ignored
  r = run(mw, { 'x-api-key': 'secret', 'x-tenant-id': 'evil-tenant' });
  assert.equal(r.req.tenantId, 'tenant-1');

  // Bearer token also accepted
  r = run(mw, { authorization: 'Bearer secret' });
  assert.equal(r.req.tenantId, 'tenant-1');

  // missing / unknown key -> 401, fail closed
  r = run(mw, {});
  assert.equal(r.nexted, false);
  assert.equal(r.status, 401);
  r = run(mw, { 'x-api-key': 'wrong' });
  assert.equal(r.status, 401);
});
