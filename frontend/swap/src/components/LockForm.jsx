import { useState } from "react";
import {
  useAccount, useChainId, useReadContract, useReadContracts,
  useWriteContract, useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits, isAddress, getAddress, maxUint256 } from "viem";
import { DEX, LOCKER_ABI, ERC20_ABI, DEFAULT_CHAIN_ID } from "../config/chains.js";
import ConnectButton from "./ConnectButton.jsx";

const fmt = (v, d, p = 6) => { try { return Number(formatUnits(v ?? 0n, d)).toLocaleString(undefined, { maximumFractionDigits: p }); } catch { return "0"; } };
const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;

export default function LockForm() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const dex = DEX[chainId] || DEX[DEFAULT_CHAIN_ID];
  const locker = dex.locker;

  const [tokenAddr, setTokenAddr] = useState("");
  const [amount, setAmount] = useState("");
  const [unlockAt, setUnlockAt] = useState(""); // datetime-local
  const [err, setErr] = useState("");
  const [txHash, setTxHash] = useState(null);

  const valid = isAddress(tokenAddr);
  const token = valid ? getAddress(tokenAddr) : undefined;
  const wrongChain = isConnected && chainId !== DEFAULT_CHAIN_ID;

  const { data: meta } = useReadContracts({
    contracts: valid ? [
      { address: token, abi: ERC20_ABI, functionName: "symbol" },
      { address: token, abi: ERC20_ABI, functionName: "decimals" },
      { address: token, abi: ERC20_ABI, functionName: "balanceOf", args: [address] },
      { address: token, abi: ERC20_ABI, functionName: "allowance", args: [address, locker] },
    ] : [],
    query: { enabled: valid && !!address, refetchInterval: 10000 },
  });
  const sym = meta?.[0]?.result || "LP";
  const dec = Number(meta?.[1]?.result ?? 18);
  const bal = meta?.[2]?.result ?? 0n;
  const allow = meta?.[3]?.result ?? 0n;

  const amtWei = (() => { try { return amount ? parseUnits(amount, dec) : 0n; } catch { return 0n; } })();
  const unlockUnix = unlockAt ? Math.floor(new Date(unlockAt).getTime() / 1000) : 0;
  const needApprove = valid && amtWei > 0n && allow < amtWei;

  // existing locks
  const { data: ids, refetch: refetchIds } = useReadContract({ address: locker, abi: LOCKER_ABI, functionName: "userLockIds", args: [address], query: { enabled: !!address, refetchInterval: 15000 } });
  const { data: locks, refetch: refetchLocks } = useReadContracts({
    contracts: (ids || []).map((id) => ({ address: locker, abi: LOCKER_ABI, functionName: "getLock", args: [id] })),
    query: { enabled: !!(ids && ids.length) },
  });

  const { writeContractAsync, isPending } = useWriteContract();
  const { isLoading: mining, isSuccess: mined } = useWaitForTransactionReceipt({ hash: txHash, query: { enabled: !!txHash } });

  async function doApprove() {
    setErr("");
    try { const h = await writeContractAsync({ address: token, abi: ERC20_ABI, functionName: "approve", args: [locker, maxUint256] }); setTxHash(h); }
    catch (e) { setErr(e.shortMessage || e.message); }
  }
  async function doLock() {
    setErr(""); setTxHash(null);
    try {
      const h = await writeContractAsync({ address: locker, abi: LOCKER_ABI, functionName: "lock", args: [token, amtWei, BigInt(unlockUnix)] });
      setTxHash(h); setAmount("");
      setTimeout(() => { refetchIds(); refetchLocks(); }, 4000);
    } catch (e) { setErr(e.shortMessage || e.message); }
  }
  async function doWithdraw(id) {
    setErr(""); setTxHash(null);
    try { const h = await writeContractAsync({ address: locker, abi: LOCKER_ABI, functionName: "withdraw", args: [id] }); setTxHash(h); setTimeout(() => refetchLocks(), 4000); }
    catch (e) { setErr(e.shortMessage || e.message); }
  }

  const now = Math.floor(Date.now() / 1000);
  const myLocks = (locks || []).map((l, i) => ({ id: (ids || [])[i], ...(l.result || {}) })).filter((l) => l.owner && l.owner.toLowerCase() === address?.toLowerCase());

  return (
    <>
      <div className="field">
        <label>Token to lock (LP token, or any ERC-20)</label>
        <input className="input mono" placeholder="0x… LP / token address" value={tokenAddr} onChange={(e) => setTokenAddr(e.target.value.trim())} />
      </div>
      <div className="tokrow">
        <div className="lbl"><span>Amount</span>{valid && <span>Balance: {fmt(bal, dec)} <button className="pill" onClick={() => setAmount(formatUnits(bal, dec))}>max</button></span>}</div>
        <input className="amt" inputMode="decimal" placeholder="0.0" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
      </div>
      <div className="field">
        <label>Unlock date &amp; time</label>
        <input className="input" type="datetime-local" value={unlockAt} onChange={(e) => setUnlockAt(e.target.value)} />
      </div>

      {!isConnected || wrongChain ? <div style={{ marginTop: 14 }}><ConnectButton /></div>
        : !valid ? <button className="btn" disabled>Enter a token address</button>
        : amtWei === 0n ? <button className="btn" disabled>Enter an amount</button>
        : !(unlockUnix > now) ? <button className="btn" disabled>Pick a future unlock time</button>
        : needApprove ? <button className="btn" disabled={isPending || mining} onClick={doApprove}>{isPending || mining ? "Approving…" : `Approve ${sym}`}</button>
        : <button className="btn" disabled={isPending || mining} onClick={doLock}>{isPending ? "Confirm in wallet…" : mining ? "Locking…" : "Lock tokens"}</button>}

      {err && <div className="err">{err}</div>}
      {mined && txHash && <div className="ok">Confirmed. <a href={`https://testnet.gembascan.io/tx/${txHash}`} target="_blank" rel="noreferrer">View</a></div>}

      {myLocks.length > 0 && (
        <div style={{ marginTop: 20 }}>
          <div className="sub" style={{ marginBottom: 6 }}>Your locks</div>
          {myLocks.map((l) => {
            const matured = Number(l.unlockTime) <= now;
            return (
              <div className="lock" key={String(l.id)}>
                <div className="top"><span className="mono">{short(l.token)}</span><span>{fmt(l.amount, 18)}</span></div>
                <div className="meta2">
                  {l.withdrawn ? "Withdrawn" : `Unlocks ${new Date(Number(l.unlockTime) * 1000).toLocaleString()}`}
                  {!l.withdrawn && (matured ? " · ready" : " · locked")}
                </div>
                {!l.withdrawn && (
                  <button className="btn" disabled={!matured || isPending || mining} onClick={() => doWithdraw(l.id)}>
                    {matured ? "Withdraw" : "Locked"}
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}
    </>
  );
}
