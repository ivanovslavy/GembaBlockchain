// Authentication for the access-control API (audit finding #1). The tenant identity MUST be
// derived server-side from an authenticated credential — NEVER taken from a client-supplied
// header. RLS keys off `app.current_tenant`, so a spoofable tenant id = full cross-tenant
// access. Each institution gets an API key mapped to its tenant UUID.

/**
 * Parse the `ACCESS_API_KEYS` env (format: `key1:tenantUuid1,key2:tenantUuid2`) into a Map.
 * Keys are opaque secrets provisioned per institution; store them in the secret store, never
 * commit them (CLAUDE.md §3).
 */
export function parseApiKeys(raw) {
  const map = new Map();
  for (const pair of String(raw || '').split(',')) {
    const idx = pair.indexOf(':');
    if (idx <= 0) continue;
    const key = pair.slice(0, idx).trim();
    const tenant = pair.slice(idx + 1).trim();
    if (key && tenant) map.set(key, tenant);
  }
  return map;
}

/**
 * Express middleware: require a valid `x-api-key` (or `Authorization: Bearer <key>`), and set
 * `req.tenantId` from the key→tenant map. Fails closed: unknown/missing key → 401; the
 * client-supplied `x-tenant-id` is ignored entirely.
 */
export function apiKeyAuth(keyMap) {
  return (req, res, next) => {
    const bearer = (req.header('authorization') || '').replace(/^Bearer\s+/i, '').trim();
    const key = req.header('x-api-key') || bearer;
    const tenantId = key ? keyMap.get(key) : undefined;
    if (!tenantId) {
      return res.status(401).json({ error: 'Unauthorized', message: 'valid x-api-key required' });
    }
    req.tenantId = tenantId; // derived from the credential, not from any client header
    next();
  };
}
