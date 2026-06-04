import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  requireEvmAddress,
  requireZone,
  requireUuid,
  requireNonEmptyString,
  optionalEmail,
  ValidationError,
} from '../src/validation.js';

const ADDR = '0x' + 'a'.repeat(40);
const UUID = '11111111-2222-3333-4444-555555555555';

test('requireEvmAddress accepts a valid address', () => {
  assert.equal(requireEvmAddress('wallet', ADDR), ADDR);
});

test('requireEvmAddress rejects malformed input (fail loud)', () => {
  assert.throws(() => requireEvmAddress('wallet', '0x123'), ValidationError);
  assert.throws(() => requireEvmAddress('wallet', undefined), ValidationError);
});

test('requireZone accepts 0 and positive integers, rejects negative/non-int', () => {
  assert.equal(requireZone('zone', 0), 0);
  assert.equal(requireZone('zone', 42), 42);
  assert.throws(() => requireZone('zone', -1), ValidationError);
  assert.throws(() => requireZone('zone', 1.5), ValidationError);
});

test('requireUuid validates UUID shape', () => {
  assert.equal(requireUuid('id', UUID), UUID);
  assert.throws(() => requireUuid('id', 'not-a-uuid'), ValidationError);
});

test('requireNonEmptyString rejects empty/oversized', () => {
  assert.equal(requireNonEmptyString('name', 'Ada'), 'Ada');
  assert.throws(() => requireNonEmptyString('name', '  '), ValidationError);
  assert.throws(() => requireNonEmptyString('name', 'x'.repeat(300)), ValidationError);
});

test('optionalEmail allows empty, validates otherwise', () => {
  assert.equal(optionalEmail('email', ''), null);
  assert.equal(optionalEmail('email', undefined), null);
  assert.equal(optionalEmail('email', 'a@b.co'), 'a@b.co');
  assert.throws(() => optionalEmail('email', 'nope'), ValidationError);
});
