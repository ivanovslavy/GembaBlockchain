// Brutal hacker attack harness vs the LIVE GmbCollector. Every attack MUST fail.
// Run: node security/collector-attack.mjs   (needs ethers; FUNDER_PK + RPC via env)
import { JsonRpcProvider, Wallet, Contract, Interface, parseEther, isError } from 'ethers';

const RPC = process.env.RPC || 'https://rpc1.gembascan.io';
const CHAIN = 821207;
const COLLECTOR = process.env.COLLECTOR || '0x72F771d2CaC82Dd807435b03D3a216006413614c';
const RECIPIENT = '0x8eB8Bf106EbC9834a2586D04F73866C7436Ce298';
const FUNDER = process.env.FUNDER_PK;

const ABI = [
  'function pay(string orderId) payable',
  'function isOrderPaid(string orderId) view returns (bool)',
  'function setRecipient(address newRecipient)',
  'function recipient() view returns (address)',
  'function paymentCount() view returns (uint256)',
];
const provider = new JsonRpcProvider(RPC, CHAIN, { staticNetwork: true });
const funder = new Wallet(FUNDER, provider);
let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log('  \x1b[32mDEFENDED\x1b[0m', m); };
const bad = (m) => { fail++; console.log('  \x1b[31mVULNERABLE\x1b[0m', m); };

async function fundNew(gmb) {
  const w = Wallet.createRandom().connect(provider);
  const tx = await funder.sendTransaction({ to: w.address, value: parseEther(String(gmb)) });
  await tx.wait(1);
  return w;
}
const reverted = (e) => isError(e, 'CALL_EXCEPTION') || /revert|reverted|already|not allowed|paused|exceeds|insufficient/i.test(e?.shortMessage || e?.message || '');

async function main() {
  console.log(`Attacking GmbCollector ${COLLECTOR} on chain ${CHAIN}\n`);
  const recip0 = await provider.getBalance(RECIPIENT);

  // ATTACK 1 — sequential double-pay
  console.log('ATTACK 1: sequential double-pay (same orderId twice)');
  const a1 = await fundNew(3);
  const c1 = new Contract(COLLECTOR, ABI, a1);
  const oid1 = 'atk-seq-' + a1.address.slice(2, 10);
  await (await c1.pay(oid1, { value: parseEther('1'), gasLimit: 120000 })).wait(1);
  try { await (await c1.pay(oid1, { value: parseEther('1'), gasLimit: 120000 })).wait(1); bad('2nd payment of same order SUCCEEDED'); }
  catch (e) { reverted(e) ? ok('double-pay rejected (OrderAlreadyPaid)') : bad('unexpected: ' + e.message); }

  // ATTACK 2 — RACE double-pay: two payers, same orderId, fired together
  console.log('ATTACK 2: concurrent race double-pay (2 wallets, same orderId)');
  const r1 = await fundNew(3); const r2 = await fundNew(3); // fund sequentially (funder nonce), race the PAY only
  const oidR = 'atk-race-' + Date.now().toString(36);
  const cc1 = new Contract(COLLECTOR, ABI, r1), cc2 = new Contract(COLLECTOR, ABI, r2);
  const results = await Promise.allSettled([
    cc1.pay(oidR, { value: parseEther('1'), gasLimit: 120000 }).then((t) => t.wait(1)),
    cc2.pay(oidR, { value: parseEther('1'), gasLimit: 120000 }).then((t) => t.wait(1)),
  ]);
  const ok1 = results.filter((r) => r.status === 'fulfilled' && r.value && r.value.status === 1).length;
  ok1 === 1 ? ok(`race: exactly 1/2 payments mined (${ok1})`) : bad(`race: ${ok1}/2 payments mined — DOUBLE PAY!`);

  // ATTACK 3 — direct GMB send (no pay())
  console.log('ATTACK 3: direct GMB transfer to the contract');
  const a3 = await fundNew(2);
  try { await (await a3.sendTransaction({ to: COLLECTOR, value: parseEther('1'), gasLimit: 60000 })).wait(1); bad('direct send accepted'); }
  catch (e) { reverted(e) ? ok('direct send rejected') : bad('unexpected: ' + e.message); }

  // ATTACK 4 — setRecipient as non-owner (hijack the payout address)
  console.log('ATTACK 4: setRecipient from a non-owner (payout hijack)');
  const a4 = await fundNew(1);
  const c4 = new Contract(COLLECTOR, ABI, a4);
  try { await (await c4.setRecipient(a4.address, { gasLimit: 80000 })).wait(1); bad('NON-OWNER changed recipient!'); }
  catch (e) { reverted(e) ? ok('setRecipient blocked for non-owner') : bad('unexpected: ' + e.message); }

  // ATTACK 5 — malformed: zero value + empty orderId
  console.log('ATTACK 5: malformed inputs (zero value, empty orderId)');
  const a5 = await fundNew(2);
  const c5 = new Contract(COLLECTOR, ABI, a5);
  try { await (await c5.pay('x', { value: 0, gasLimit: 120000 })).wait(1); bad('zero-value pay accepted'); }
  catch (e) { reverted(e) ? ok('zero-value rejected') : bad('unexpected: ' + e.message); }
  try { await (await c5.pay('', { value: parseEther('1'), gasLimit: 120000 })).wait(1); bad('empty-orderId pay accepted'); }
  catch (e) { reverted(e) ? ok('empty-orderId rejected') : bad('unexpected: ' + e.message); }

  // integrity: recipient only ever credited by successful pays; contract holds nothing
  const held = await provider.getBalance(COLLECTOR);
  held === 0n ? ok('contract holds 0 GMB (forwards everything, custodies nothing)') : bad(`contract holds ${held} wei`);
  const recip1 = await provider.getBalance(RECIPIENT);
  console.log(`\n  recipient received +${(recip1 - recip0)} wei across the legit pays`);
  console.log(`\n==== ${pass} DEFENDED, ${fail} VULNERABLE ====`);
  process.exit(fail ? 1 : 0);
}
main().catch((e) => { console.error('harness error', e); process.exit(2); });
