// Pure validation (no deps) so unit tests run without ethers installed.
const EVM_ADDRESS = /^0x[0-9a-fA-F]{40}$/;

export function isEvmAddress(a) {
  return typeof a === 'string' && EVM_ADDRESS.test(a);
}
