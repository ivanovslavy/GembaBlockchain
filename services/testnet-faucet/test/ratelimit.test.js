import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CooldownLimiter } from '../src/ratelimit.js';
import { isEvmAddress } from '../src/validation.js';

test('first acquire succeeds, second within cooldown fails', () => {
  const rl = new CooldownLimiter(1000);
  assert.equal(rl.tryAcquire('0xabc', 0), true);
  assert.equal(rl.tryAcquire('0xabc', 500), false);
  assert.equal(rl.remaining('0xabc', 500), 500);
});

test('acquire succeeds again after the cooldown elapses', () => {
  const rl = new CooldownLimiter(1000);
  rl.tryAcquire('0xabc', 0);
  assert.equal(rl.tryAcquire('0xabc', 1000), true);
});

test('different keys are independent', () => {
  const rl = new CooldownLimiter(1000);
  assert.equal(rl.tryAcquire('a', 0), true);
  assert.equal(rl.tryAcquire('b', 0), true);
});

test('release rolls back so a failed drip does not burn the window', () => {
  const rl = new CooldownLimiter(1000);
  rl.tryAcquire('0xabc', 0);
  rl.release('0xabc');
  assert.equal(rl.tryAcquire('0xabc', 1), true); // can retry immediately
});

test('isEvmAddress validates 0x addresses', () => {
  assert.equal(isEvmAddress('0x' + 'a'.repeat(40)), true);
  assert.equal(isEvmAddress('0x123'), false);
  assert.equal(isEvmAddress(undefined), false);
});
