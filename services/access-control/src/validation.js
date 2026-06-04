// Input validation for the access-control API. Pure (no deps) so it is unit-test
// runnable without a DB. Mirrors the Solidity security standards on the off-chain
// side: validate every external input up front, fail loud with a clear error.

export class ValidationError extends Error {
  constructor(field, message) {
    super(`${field}: ${message}`);
    this.name = 'ValidationError';
    this.field = field;
    this.status = 400;
  }
}

const EVM_ADDRESS = /^0x[0-9a-fA-F]{40}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function requireEvmAddress(field, value) {
  if (typeof value !== 'string' || !EVM_ADDRESS.test(value)) {
    throw new ValidationError(field, 'must be a 0x-prefixed 20-byte address');
  }
  return value;
}

export function requireUuid(field, value) {
  if (typeof value !== 'string' || !UUID.test(value)) {
    throw new ValidationError(field, 'must be a UUID');
  }
  return value;
}

export function requireZone(field, value) {
  // zones are non-negative integers; they match the on-chain ERC-1155 token id.
  if (!Number.isInteger(value) || value < 0) {
    throw new ValidationError(field, 'must be a non-negative integer');
  }
  return value;
}

export function requireNonEmptyString(field, value, max = 256) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new ValidationError(field, 'is required');
  }
  if (value.length > max) {
    throw new ValidationError(field, `must be at most ${max} chars`);
  }
  return value;
}

export function optionalEmail(field, value) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' || !value.includes('@') || value.length > 320) {
    throw new ValidationError(field, 'must be a valid email');
  }
  return value;
}
