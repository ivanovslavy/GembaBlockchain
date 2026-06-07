import "dotenv/config";
import { generateWallets } from "../lib/wallets.js";

const n = Number(process.env.WALLET_COUNT || 300);
const w = generateWallets(n);
console.log(`✓ generated ${w.length} wallets → wallets.json  (private keys saved; file is gitignored)`);
console.log(`  first: ${w[0].address}   last: ${w[w.length - 1].address}`);
