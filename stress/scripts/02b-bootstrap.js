import "dotenv/config";
import { Interface } from "ethers";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { makeProviders } from "../lib/provider.js";
import { loadWallets, asSigners } from "../lib/wallets.js";
import { NonceManager } from "../lib/nonceManager.js";
import { Semaphore } from "../lib/rateLimiter.js";
import { feeOverrides, sendRaw } from "../lib/tx.js";

// One-time per-wallet bootstrap so the load run reflects the chain, not setup noise:
// each wallet mints ST0/ST1 + ERC1155(id=index) to itself and approves the DEX.
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const art = (n) => JSON.parse(readFileSync(join(root, "artifacts", `${n}.json`), "utf8"));
const env = process.env;
const dep = JSON.parse(readFileSync(join(root, "deployed.json"), "utf8"));
const A = dep.addresses;
const erc20 = new Interface(art("StressERC20").abi);
const erc1155 = new Interface(art("StressERC1155").abi);

const providers = makeProviders(env.RPC_URLS.split(","), env.CHAIN_ID);
const signers = asSigners(loadWallets(), providers);
const fee = feeOverrides(env);
const chainId = Number(env.CHAIN_ID);
const nonceMgr = new NonceManager();
const sem = new Semaphore(200);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

for (let i = 0; i < signers.length; i += 50)
  await Promise.all(signers.slice(i, i + 50).map((s) => nonceMgr.init(s.address, providers.next()).catch(() => 0)));

let ok = 0, fail = 0;
console.log(`bootstrapping ${signers.length} wallets (mint ST0/ST1 + ERC1155, approve DEX)…`);
const jobs = [];
for (const s of signers) {
  const ops = [
    { to: A.t0, data: erc20.encodeFunctionData("mint", [s.address, 10n ** 24n]), gas: 70000n },
    { to: A.t1, data: erc20.encodeFunctionData("mint", [s.address, 10n ** 24n]), gas: 70000n },
    { to: A.t0, data: erc20.encodeFunctionData("approve", [A.dex, 1n << 255n]), gas: 60000n },
    { to: A.t1, data: erc20.encodeFunctionData("approve", [A.dex, 1n << 255n]), gas: 60000n },
    { to: A.erc1155, data: erc1155.encodeFunctionData("mint", [s.address, BigInt(s.index), 1000000n]), gas: 70000n },
  ];
  jobs.push((async () => {
    for (const op of ops) {
      await sem.acquire();
      try { await sendRaw(s, s.provider(), nonceMgr, op, fee, chainId); ok++; }
      catch { fail++; }
      finally { sem.release(); }
    }
  })());
}
await Promise.all(jobs);
console.log(`  submitted ok=${ok} fail=${fail}; waiting for inclusion…`);
await sleep(45000);
const c = signers[0];
const bal = await providers.primary.call({ to: A.t0, data: erc20.encodeFunctionData("balanceOf", [c.address]) });
console.log(`✓ bootstrap done. sample ${c.address} ST0 balance set: ${BigInt(bal) > 0n}`);
process.exit(0);
