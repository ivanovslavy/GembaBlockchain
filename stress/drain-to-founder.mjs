import "dotenv/config";
import { Wallet, JsonRpcProvider, Network, parseUnits, parseEther, formatEther } from "ethers";
import { readFileSync } from "node:fs";
const FOUNDER = "0x5578c75F22dE0bf1caA4BdD46BA28406C696a5dC";
const net = Network.from(Number(process.env.CHAIN_ID));
const p = new JsonRpcProvider("http://127.0.0.1:8545", net, { staticNetwork: net });
const arr = JSON.parse(readFileSync("/root/stress/wallets.json"));
const wallets = Array.isArray(arr) ? arr : (arr.wallets || arr.accounts || []);
const blk = await p.getBlock("latest");
const base = blk.baseFeePerGas || parseUnits("5","gwei");
const maxFee = base * 3n + parseUnits("1","gwei");
const tip = parseUnits("1","gwei");
const gasResv = 21000n * maxFee;
console.log("draining", wallets.length, "wallets -> founder", FOUNDER);
let sumWallets = 0n, returned = 0n; const sent = [];
for (let i=0;i<wallets.length;i++){
  const sw = new Wallet(wallets[i].privateKey, p);
  const bal = await p.getBalance(sw.address);
  sumWallets += bal;
  if (bal > gasResv){
    const value = bal - gasResv;
    try { const tx = await sw.sendTransaction({to:FOUNDER,value,maxFeePerGas:maxFee,maxPriorityFeePerGas:tip,gasLimit:21000n}); sent.push(tx.hash); returned += value; } catch(e){ console.log("  skip",i,e.message.slice(0,60)); }
  }
  if((i+1)%75===0) console.log("  processed",i+1);
}
// drain funder
const funder = new Wallet(process.env.FUNDER_PK, p);
const fbal = await p.getBalance(funder.address);
console.log("funder bal:", formatEther(fbal));
if (fbal > gasResv){ const tx = await funder.sendTransaction({to:FOUNDER,value:fbal-gasResv,maxFeePerGas:maxFee,maxPriorityFeePerGas:tip,gasLimit:21000n}); sent.push(tx.hash); returned += (fbal-gasResv); }
console.log("submitted", sent.length, "drain txs; waiting for last...");
if(sent.length) await p.waitForTransaction(sent[sent.length-1],1);
const funded = parseEther("4500");
const gasSpent = funded - sumWallets;
console.log("=== REPORT ===");
console.log("worker wallets funded total: 4500 GMB");
console.log("worker wallets balance at end:", formatEther(sumWallets), "GMB");
console.log("=> GAS SPENT overnight (B+C, workers):", formatEther(gasSpent), "GMB");
console.log("RETURNED to founder:", formatEther(returned), "GMB");
console.log("UNRECOVERABLE (stuck in dead Disperse 0x4731EDb):", "1500 GMB (testnet, dead contract)");
