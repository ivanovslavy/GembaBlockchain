import { useMemo, useState } from "react";
import { useAccount, useChainId, useBalance, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { readContracts } from "wagmi/actions";
import { parseUnits, formatUnits, isAddress, getAddress, maxUint256 } from "viem";
import { DEX, NATIVE, ROUTER_ABI, ERC20_ABI, wagmiConfig, DEFAULT_CHAIN_ID } from "../config/chains.js";
import ConnectButton from "./ConnectButton.jsx";

const fmt = (v, d, p = 6) => { try { const n = Number(formatUnits(v, d)); return n.toLocaleString(undefined, { maximumFractionDigits: p }); } catch { return "0"; } };
const parse = (a, d) => { try { return a ? parseUnits(a, d) : 0n; } catch { return 0n; } };

export default function SwapForm() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const dex = DEX[chainId] || DEX[DEFAULT_CHAIN_ID];
  const wgmbToken = { address: dex.wgmb, symbol: "WGMB", name: "Wrapped GMB", decimals: 18 };

  const [tokens, setTokens] = useState([NATIVE, wgmbToken]);
  const [tIn, setTIn] = useState(NATIVE);
  const [tOut, setTOut] = useState(wgmbToken);
  const [amount, setAmount] = useState("");
  const [slip, setSlip] = useState("0.5");
  const [picking, setPicking] = useState(null); // 'in' | 'out' | null
  const [err, setErr] = useState("");
  const [txHash, setTxHash] = useState(null);

  const amountIn = parse(amount, tIn.decimals);
  const wrapAddr = (t) => (t.isNative ? getAddress(dex.wgmb) : getAddress(t.address));
  const path = useMemo(() => {
    if (tIn.isNative) return [getAddress(dex.wgmb), wrapAddr(tOut)];
    if (tOut.isNative) return [wrapAddr(tIn), getAddress(dex.wgmb)];
    return [wrapAddr(tIn), wrapAddr(tOut)];
  }, [tIn, tOut]);
  const samePair = wrapAddr(tIn).toLowerCase() === wrapAddr(tOut).toLowerCase();

  // quote
  const { data: amountsOut, isError: quoteErr } = useReadContract({
    address: dex.router, abi: ROUTER_ABI, functionName: "getAmountsOut", args: [amountIn, path],
    query: { enabled: !!address && amountIn > 0n && !samePair, refetchInterval: 8000 },
  });
  const out = amountsOut ? amountsOut[amountsOut.length - 1] : 0n;
  const slipBps = BigInt(Math.round(Number(slip || "0.5") * 100));
  const minOut = out - (out * slipBps) / 10000n;

  // balances
  const { data: balNative } = useBalance({ address, query: { enabled: !!address && tIn.isNative } });
  const { data: balErc } = useReadContract({ address: tIn.isNative ? undefined : tIn.address, abi: ERC20_ABI, functionName: "balanceOf", args: [address], query: { enabled: !!address && !tIn.isNative } });
  const balIn = tIn.isNative ? (balNative?.value ?? 0n) : (balErc ?? 0n);

  // allowance (erc20 in)
  const { data: allowance, refetch: refetchAllow } = useReadContract({ address: tIn.isNative ? undefined : tIn.address, abi: ERC20_ABI, functionName: "allowance", args: [address, dex.router], query: { enabled: !!address && !tIn.isNative } });
  const needApprove = !tIn.isNative && amountIn > 0n && (allowance ?? 0n) < amountIn;

  const { writeContractAsync, isPending } = useWriteContract();
  const { isLoading: mining, isSuccess: mined } = useWaitForTransactionReceipt({ hash: txHash, query: { enabled: !!txHash } });

  function flip() { setTIn(tOut); setTOut(tIn); setAmount(""); }

  async function importToken(addr) {
    setErr("");
    if (!isAddress(addr)) { setErr("Invalid address."); return; }
    try {
      const [sym, dec] = await readContracts(wagmiConfig, { contracts: [
        { address: getAddress(addr), abi: ERC20_ABI, functionName: "symbol" },
        { address: getAddress(addr), abi: ERC20_ABI, functionName: "decimals" },
      ] });
      const t = { address: getAddress(addr), symbol: sym.result || "TOKEN", name: sym.result || "Token", decimals: Number(dec.result ?? 18) };
      setTokens((p) => (p.find((x) => !x.isNative && x.address?.toLowerCase() === t.address.toLowerCase()) ? p : [...p, t]));
      (picking === "in" ? setTIn : setTOut)(t); setPicking(null);
    } catch { setErr("Could not read token (not an ERC-20?)."); }
  }

  async function doApprove() {
    setErr("");
    try { const h = await writeContractAsync({ address: tIn.address, abi: ERC20_ABI, functionName: "approve", args: [dex.router, maxUint256] }); setTxHash(h); await refetchAllow(); }
    catch (e) { setErr(e.shortMessage || e.message); }
  }
  async function doSwap() {
    setErr(""); setTxHash(null);
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 1200);
    try {
      let h;
      if (tIn.isNative) h = await writeContractAsync({ address: dex.router, abi: ROUTER_ABI, functionName: "swapExactETHForTokens", args: [minOut, path, address, deadline], value: amountIn });
      else if (tOut.isNative) h = await writeContractAsync({ address: dex.router, abi: ROUTER_ABI, functionName: "swapExactTokensForETH", args: [amountIn, minOut, path, address, deadline] });
      else h = await writeContractAsync({ address: dex.router, abi: ROUTER_ABI, functionName: "swapExactTokensForTokens", args: [amountIn, minOut, path, address, deadline] });
      setTxHash(h); setAmount("");
    } catch (e) { setErr(e.shortMessage || e.message); }
  }

  const rate = out > 0n && amountIn > 0n ? (Number(formatUnits(out, tOut.decimals)) / Number(formatUnits(amountIn, tIn.decimals))) : 0;
  const insufficient = amountIn > balIn;
  const wrongChain = isConnected && chainId !== DEFAULT_CHAIN_ID;

  return (
    <>
      <div className="tokrow">
        <div className="lbl"><span>You pay</span>{address && <span>Balance: {fmt(balIn, tIn.decimals)} {tIn.symbol}</span>}</div>
        <div className="line">
          <input className="amt" inputMode="decimal" placeholder="0.0" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
          <button className="tokbtn" onClick={() => setPicking("in")}>{tIn.symbol} ▾</button>
        </div>
      </div>

      <div className="flip"><button onClick={flip} title="flip">⇅</button></div>

      <div className="tokrow">
        <div className="lbl"><span>You receive</span></div>
        <div className="line">
          <input className="amt" placeholder="0.0" value={out > 0n ? fmt(out, tOut.decimals) : ""} readOnly />
          <button className="tokbtn" onClick={() => setPicking("out")}>{tOut.symbol} ▾</button>
        </div>
      </div>

      {amountIn > 0n && out > 0n && (
        <div className="meta">
          <div className="r"><span>Rate</span><span>1 {tIn.symbol} ≈ {rate.toLocaleString(undefined, { maximumFractionDigits: 6 })} {tOut.symbol}</span></div>
          <div className="r"><span>Min received</span><span>{fmt(minOut, tOut.decimals)} {tOut.symbol}</span></div>
          <div className="r"><span>Slippage</span><span className="slip"><input value={slip} onChange={(e) => setSlip(e.target.value.replace(/[^0-9.]/g, ""))} />%</span></div>
        </div>
      )}

      {!isConnected ? <div style={{ marginTop: 14 }}><ConnectButton /></div>
        : wrongChain ? <div style={{ marginTop: 14 }}><ConnectButton /></div>
        : samePair ? <button className="btn" disabled>Select two different tokens</button>
        : insufficient ? <button className="btn" disabled>Insufficient {tIn.symbol}</button>
        : amountIn === 0n ? <button className="btn" disabled>Enter an amount</button>
        : quoteErr || out === 0n ? <button className="btn" disabled>No liquidity for this pair</button>
        : needApprove ? <button className="btn" disabled={isPending || mining} onClick={doApprove}>{isPending || mining ? "Approving…" : `Approve ${tIn.symbol}`}</button>
        : <button className="btn" disabled={isPending || mining} onClick={doSwap}>{isPending ? "Confirm in wallet…" : mining ? "Swapping…" : "Swap"}</button>}

      {err && <div className="err">{err}</div>}
      {mined && txHash && <div className="ok">✓ Swap confirmed. <a href={`https://testnet.gembascan.io/tx/${txHash}`} target="_blank" rel="noreferrer">View</a></div>}

      {picking && (
        <div className="modal" onClick={() => setPicking(null)}>
          <div className="card" onClick={(e) => e.stopPropagation()}>
            <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 12 }}><b style={{ color: "var(--heading)" }}>Select token</b><button className="pill" onClick={() => setPicking(null)}>✕</button></div>
            {tokens.map((t) => (
              <div className="tokopt" key={t.address || "native"} onClick={() => { (picking === "in" ? setTIn : setTOut)(t); setPicking(null); }}>
                <span className="dot" style={{ width: 26, height: 26, borderRadius: 99, background: "var(--grad)", display: "inline-block" }} />
                <div><div style={{ color: "var(--heading)", fontWeight: 700 }}>{t.symbol}</div><div style={{ fontSize: 12, color: "var(--text-dim)" }}>{t.name}</div></div>
              </div>
            ))}
            <div style={{ marginTop: 12 }}>
              <div style={{ fontSize: 12, color: "var(--text-dim)", marginBottom: 6 }}>Import by address</div>
              <input className="addr" placeholder="0x…" onKeyDown={(e) => { if (e.key === "Enter") importToken(e.target.value.trim()); }} />
            </div>
            {err && <div className="err">{err}</div>}
          </div>
        </div>
      )}
    </>
  );
}
