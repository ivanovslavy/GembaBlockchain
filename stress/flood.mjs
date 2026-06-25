// Lightweight distributed flooder: hammer rpc1/2/3 round-robin at target concurrency
// for DURATION sec, count HTTP status codes + achieved req/s. Node 18+ global fetch.
const DUR = Number(process.argv[2] || 30);
const CONC = Number(process.argv[3] || 80);
const EPS = ["https://rpc1.gembascan.io","https://rpc2.gembascan.io","https://rpc3.gembascan.io"];
const body = JSON.stringify({jsonrpc:"2.0",id:1,method:"eth_blockNumber",params:[]});
const counts = {}; let sent=0; const t0=Date.now(); let i=0;
const stop = () => Date.now()-t0 >= DUR*1000;
async function worker(){
  while(!stop()){
    const url = EPS[(i++)%3];
    try{
      const r = await fetch(url,{method:"POST",headers:{"content-type":"application/json"},body,signal:AbortSignal.timeout(8000)});
      counts[r.status]=(counts[r.status]||0)+1;
    }catch(e){ counts["ERR"]=(counts["ERR"]||0)+1; }
    sent++;
  }
}
await Promise.all(Array.from({length:CONC},()=>worker()));
const secs=(Date.now()-t0)/1000;
console.log(`sent=${sent} in ${secs.toFixed(1)}s = ${(sent/secs).toFixed(0)} req/s | codes=${JSON.stringify(counts)}`);
