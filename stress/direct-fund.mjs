import "dotenv/config";
import { Wallet, JsonRpcProvider, Network, parseEther, parseUnits, formatEther } from "ethers";
import { loadWallets } from "./lib/wallets.js";
const net = Network.from(Number(process.env.CHAIN_ID));
const p = new JsonRpcProvider(process.env.RPC_URLS.split(",")[0].trim(), net, { staticNetwork: net });
const funder = new Wallet(process.env.FUNDER_PK, p);
const wallets = loadWallets();
const per = parseEther("15");
const maxFee = parseUnits(String(process.env.MAX_FEE_GWEI||"3"), "gwei");
const tip = parseUnits(String(process.env.PRIORITY_FEE_GWEI||"1"), "gwei");
let nonce = await p.getTransactionCount(funder.address, "latest");
console.log("direct-funding", wallets.length, "wallets x 15 GMB from", funder.address);
const sent = [];
for (let i=0;i<wallets.length;i++){
  const tx = await funder.sendTransaction({to:wallets[i].address,value:per,nonce:nonce++,maxFeePerGas:maxFee,maxPriorityFeePerGas:tip,gasLimit:21000n});
  sent.push(tx.hash);
  if((i+1)%75===0) console.log("  sent",i+1);
}
console.log("all", sent.length, "submitted; waiting for last to mine...");
await p.waitForTransaction(sent[sent.length-1],1);
for (const i of [0,1,150,299]) console.log("wallet["+i+"]",formatEther(await p.getBalance(wallets[i].address)),"GMB");
console.log("funder left:",formatEther(await p.getBalance(funder.address)),"GMB");
