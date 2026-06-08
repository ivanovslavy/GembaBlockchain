import { useState } from "react";
import {
  useAccount, useChainId, useBalance, useReadContract, useReadContracts,
  useWriteContract, useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits, isAddress, getAddress, maxUint256, zeroAddress } from "viem";
import { DEX, ROUTER_ABI, FACTORY_ABI, PAIR_ABI, ERC20_ABI, DEFAULT_CHAIN_ID } from "../config/chains.js";
import ConnectButton from "./ConnectButton.jsx";

const fmt = (v, d, p = 6) => { try { return Number(formatUnits(v ?? 0n, d)).toLocaleString(undefined, { maximumFractionDigits: p }); } catch { return "0"; } };
const parse = (a, d) => { try { return a ? parseUnits(a, d) : 0n; } catch { return 0n; } };
const minus = (v, bps) => v - (v * bps) / 10000n;

export default function LiquidityForm() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const dex = DEX[chainId] || DEX[DEFAULT_CHAIN_ID];
  const wgmb = getAddress(dex.wgmb);

  const [mode, setMode] = useState("add"); // add | remove
  const [tokenAddr, setTokenAddr] = useState("");
  const [fot, setFot] = useState(false);
  const [slip, setSlip] = useState("0.5");
  const [amtToken, setAmtToken] = useState("");
  const [amtGmbManual, setAmtGmbManual] = useState(""); // only used when the pool is new
  const [lpAmt, setLpAmt] = useState("");
  const [err, setErr] = useState("");
  const [txHash, setTxHash] = useState(null);

  const valid = isAddress(tokenAddr);
  const token = valid ? getAddress(tokenAddr) : undefined;
  const wrongChain = isConnected && chainId !== DEFAULT_CHAIN_ID;
  const slipBps = BigInt(Math.round(Number(slip || "0.5") * 100));

  const { data: meta } = useReadContracts({
    contracts: valid ? [
      { address: token, abi: ERC20_ABI, functionName: "symbol" },
      { address: token, abi: ERC20_ABI, functionName: "decimals" },
      { address: token, abi: ERC20_ABI, functionName: "balanceOf", args: [address] },
      { address: token, abi: ERC20_ABI, functionName: "allowance", args: [address, dex.router] },
    ] : [],
    query: { enabled: valid && !!address, refetchInterval: 10000 },
  });
  const sym = meta?.[0]?.result || "TOKEN";
  const dec = Number(meta?.[1]?.result ?? 18);
  const tokBal = meta?.[2]?.result ?? 0n;
  const tokAllow = meta?.[3]?.result ?? 0n;

  const { data: pair } = useReadContract({ address: dex.factory, abi: FACTORY_ABI, functionName: "getPair", args: [token, wgmb], query: { enabled: valid } });
  const hasPair = pair && pair !== zeroAddress;

  const { data: pd } = useReadContracts({
    contracts: hasPair ? [
      { address: pair, abi: PAIR_ABI, functionName: "getReserves" },
      { address: pair, abi: PAIR_ABI, functionName: "token0" },
      { address: pair, abi: PAIR_ABI, functionName: "totalSupply" },
      { address: pair, abi: ERC20_ABI, functionName: "balanceOf", args: [address] },
      { address: pair, abi: ERC20_ABI, functionName: "allowance", args: [address, dex.router] },
    ] : [],
    query: { enabled: !!hasPair && !!address, refetchInterval: 10000 },
  });
  const reserves = pd?.[0]?.result;
  const token0 = pd?.[1]?.result;
  const lpTotal = pd?.[2]?.result ?? 0n;
  const lpBal = pd?.[3]?.result ?? 0n;
  const lpAllow = pd?.[4]?.result ?? 0n;

  let rToken = 0n, rGmb = 0n;
  if (reserves && token0) {
    const t0IsToken = token0.toLowerCase() === token?.toLowerCase();
    rToken = t0IsToken ? reserves[0] : reserves[1];
    rGmb = t0IsToken ? reserves[1] : reserves[0];
  }
  const pooled = hasPair && rToken > 0n && rGmb > 0n;

  const { data: gmbBal } = useBalance({ address, query: { enabled: !!address } });

  // --- ADD amounts ---
  const amtTokenWei = parse(amtToken, dec);
  const amtGmbWei = pooled ? (rToken > 0n ? (amtTokenWei * rGmb) / rToken : 0n) : parse(amtGmbManual, 18);
  const needApproveToken = mode === "add" && !fot && tokAllow < amtTokenWei; // (fot still needs approve; see below)
  const needTokenApproval = mode === "add" && tokAllow < amtTokenWei && amtTokenWei > 0n;

  // --- REMOVE amounts ---
  const lpWei = parse(lpAmt, 18);
  const outToken = lpTotal > 0n ? (lpWei * rToken) / lpTotal : 0n;
  const outGmb = lpTotal > 0n ? (lpWei * rGmb) / lpTotal : 0n;
  const needLpApproval = mode === "remove" && lpAllow < lpWei && lpWei > 0n;

  const { writeContractAsync, isPending } = useWriteContract();
  const { isLoading: mining, isSuccess: mined } = useWaitForTransactionReceipt({ hash: txHash, query: { enabled: !!txHash } });

  async function approve(tokenAddrToApprove) {
    setErr("");
    try { const h = await writeContractAsync({ address: tokenAddrToApprove, abi: ERC20_ABI, functionName: "approve", args: [dex.router, maxUint256] }); setTxHash(h); }
    catch (e) { setErr(e.shortMessage || e.message); }
  }
  async function doAdd() {
    setErr(""); setTxHash(null);
    const dl = BigInt(Math.floor(Date.now() / 1000) + 1200);
    const minTok = fot ? 0n : minus(amtTokenWei, slipBps);
    const minGmb = fot ? 0n : minus(amtGmbWei, slipBps);
    try {
      const h = await writeContractAsync({
        address: dex.router, abi: ROUTER_ABI, functionName: "addLiquidityETH",
        args: [token, amtTokenWei, minTok, minGmb, address, dl], value: amtGmbWei,
      });
      setTxHash(h); setAmtToken(""); setAmtGmbManual("");
    } catch (e) { setErr(e.shortMessage || e.message); }
  }
  async function doRemove() {
    setErr(""); setTxHash(null);
    const dl = BigInt(Math.floor(Date.now() / 1000) + 1200);
    const minTok = fot ? 0n : minus(outToken, slipBps);
    const minGmb = fot ? 0n : minus(outGmb, slipBps);
    try {
      const fn = fot ? "removeLiquidityETHSupportingFeeOnTransferTokens" : "removeLiquidityETH";
      const h = await writeContractAsync({ address: dex.router, abi: ROUTER_ABI, functionName: fn, args: [token, lpWei, minTok, minGmb, address, dl] });
      setTxHash(h); setLpAmt("");
    } catch (e) { setErr(e.shortMessage || e.message); }
  }

  return (
    <>
      <div className="tabs" style={{ marginBottom: 14 }}>
        <button className={`tab${mode === "add" ? " on" : ""}`} onClick={() => setMode("add")}>Add</button>
        <button className={`tab${mode === "remove" ? " on" : ""}`} onClick={() => setMode("remove")}>Remove</button>
      </div>

      <div className="field">
        <label>Token (paired with GMB)</label>
        <input className="input mono" placeholder="0x… token address" value={tokenAddr} onChange={(e) => setTokenAddr(e.target.value.trim())} />
      </div>

      {valid && (
        <div className="meta" style={{ marginBottom: 12 }}>
          <div className="r"><span>Pool</span><span>{hasPair ? (pooled ? `${sym} / GMB` : "exists (empty)") : "will be created"}</span></div>
          {pooled && <div className="r"><span>Rate</span><span>1 {sym} ≈ {(Number(formatUnits(rGmb, 18)) / Number(formatUnits(rToken, dec) || 1)).toLocaleString(undefined, { maximumFractionDigits: 6 })} GMB</span></div>}
        </div>
      )}

      {mode === "add" ? (
        <>
          <div className="tokrow">
            <div className="lbl"><span>{sym} amount</span>{valid && <span>Balance: {fmt(tokBal, dec)}</span>}</div>
            <input className="amt" inputMode="decimal" placeholder="0.0" value={amtToken} onChange={(e) => setAmtToken(e.target.value.replace(/[^0-9.]/g, ""))} />
          </div>
          <div className="tokrow">
            <div className="lbl"><span>GMB amount{pooled ? " (auto)" : ""}</span>{address && <span>Balance: {fmt(gmbBal?.value, 18)}</span>}</div>
            <input className="amt" inputMode="decimal" placeholder="0.0" readOnly={pooled}
              value={pooled ? (amtTokenWei > 0n ? fmt(amtGmbWei, 18) : "") : amtGmbManual}
              onChange={(e) => setAmtGmbManual(e.target.value.replace(/[^0-9.]/g, ""))} />
          </div>
        </>
      ) : (
        <>
          <div className="tokrow">
            <div className="lbl"><span>LP amount</span>{hasPair && <span>Balance: {fmt(lpBal, 18)} <button className="pill" onClick={() => setLpAmt(formatUnits(lpBal, 18))}>max</button></span>}</div>
            <input className="amt" inputMode="decimal" placeholder="0.0" value={lpAmt} onChange={(e) => setLpAmt(e.target.value.replace(/[^0-9.]/g, ""))} />
          </div>
          {lpWei > 0n && pooled && (
            <div className="meta"><div className="r"><span>You receive</span><span>{fmt(outToken, dec)} {sym} + {fmt(outGmb, 18)} GMB</span></div></div>
          )}
        </>
      )}

      <label className="check"><input type="checkbox" checked={fot} onChange={(e) => setFot(e.target.checked)} /> Fee-on-transfer (tax) token</label>
      {!fot && (
        <div className="meta"><div className="r"><span>Slippage</span><span className="slip"><input value={slip} onChange={(e) => setSlip(e.target.value.replace(/[^0-9.]/g, ""))} />%</span></div></div>
      )}

      {!isConnected || wrongChain ? <div style={{ marginTop: 14 }}><ConnectButton /></div>
        : !valid ? <button className="btn" disabled>Enter a token address</button>
        : mode === "add" ? (
          amtTokenWei === 0n || amtGmbWei === 0n ? <button className="btn" disabled>Enter amounts</button>
          : needTokenApproval ? <button className="btn" disabled={isPending || mining} onClick={() => approve(token)}>{isPending || mining ? "Approving…" : `Approve ${sym}`}</button>
          : <button className="btn" disabled={isPending || mining} onClick={doAdd}>{isPending ? "Confirm in wallet…" : mining ? "Adding…" : "Add liquidity"}</button>
        ) : (
          !hasPair || lpWei === 0n ? <button className="btn" disabled>Enter LP amount</button>
          : needLpApproval ? <button className="btn" disabled={isPending || mining} onClick={() => approve(pair)}>{isPending || mining ? "Approving…" : "Approve LP"}</button>
          : <button className="btn" disabled={isPending || mining} onClick={doRemove}>{isPending ? "Confirm in wallet…" : mining ? "Removing…" : "Remove liquidity"}</button>
        )}

      {err && <div className="err">{err}</div>}
      {mined && txHash && <div className="ok">Confirmed. <a href={`https://testnet.gembascan.io/tx/${txHash}`} target="_blank" rel="noreferrer">View</a></div>}
    </>
  );
}
