import "dotenv/config";
import { generateWallets } from "../lib/wallets.js";

const n = Number(process.env.WALLET_COUNT || 100);
const w = generateWallets(n);
console.log(`✓ generated ${w.length} wallets → endurance/wallets.json (0600, gitignored)`);
console.log(`  first: ${w[0].address}  last: ${w[w.length - 1].address}`);
