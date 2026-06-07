import "dotenv/config";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// Light check that the explorer/verify API responds for our deployed addresses after
// load (full standard-json verification is done via the existing explorer/verify flow).
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dep = JSON.parse(readFileSync(join(root, "deployed.json"), "utf8"));
const api = process.env.EXPLORER_API || "https://testnet.gembascan.io/api";

for (const [name, addr] of Object.entries(dep.addresses)) {
  try {
    const r = await fetch(`${api}?module=contract&action=getsourcecode&address=${addr}`);
    const j = await r.json();
    const verified = j?.result?.[0]?.ABI && j.result[0].ABI !== "Contract source code not verified";
    console.log(`  ${verified ? "✓ verified " : "· unverified"} ${name} ${addr}`);
  } catch (e) {
    console.log(`  ! ${name} ${addr} — explorer error: ${e.message}`);
  }
}
