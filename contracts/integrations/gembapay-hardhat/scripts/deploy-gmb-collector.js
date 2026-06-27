// Deploy + verify GmbCollector from the GembaPay hardhat project.
// Add the gemba networks (see ../README.md) to hardhat.config first, then:
//   GMB_COLLECTOR_OWNER=0x.. npx hardhat run scripts/deploy-gmb-collector.js --network gembaTestnet
// This is an ADDITIVE script — it does not touch existing GembaPay contracts or scripts.
const hre = require("hardhat");

async function main() {
  const owner = process.env.GMB_COLLECTOR_OWNER;
  const recipient = process.env.GMB_COLLECTOR_RECIPIENT || "0x8eB8Bf106EbC9834a2586D04F73866C7436Ce298";
  if (!owner) throw new Error("set GMB_COLLECTOR_OWNER");

  const F = await hre.ethers.getContractFactory("GmbCollector");
  const c = await F.deploy(owner, recipient);
  await c.waitForDeployment();
  const addr = await c.getAddress();
  console.log("GmbCollector deployed:", addr, "| owner:", owner, "| recipient:", recipient);

  // verify on GembaScan (Blockscout)
  await new Promise((r) => setTimeout(r, 6000));
  try {
    await hre.run("verify:verify", { address: addr, constructorArguments: [owner, recipient] });
    console.log("verified ✓");
  } catch (e) {
    console.log("verify (may already be verified):", e.message);
  }
}
main().catch((e) => { console.error(e); process.exit(1); });
