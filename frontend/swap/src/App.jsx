import { useState } from "react";
import ConnectButton from "./components/ConnectButton.jsx";
import SwapForm from "./components/SwapForm.jsx";
import LiquidityForm from "./components/LiquidityForm.jsx";
import LockForm from "./components/LockForm.jsx";

const TABS = [
  { key: "swap", label: "Swap" },
  { key: "liquidity", label: "Liquidity" },
  { key: "lock", label: "Lock LP" },
];

export default function App() {
  const [tab, setTab] = useState("swap");
  return (
    <>
      <header className="topbar">
        <a className="brand" href="https://gembachain.io">
          <span className="dot" /> Gemba<b>Swap</b>
        </a>
        <ConnectButton />
      </header>

      <main className="wrap">
        <div className="card">
          <div className="tabs">
            {TABS.map((t) => (
              <button key={t.key} className={`tab${tab === t.key ? " on" : ""}`} onClick={() => setTab(t.key)}>
                {t.label}
              </button>
            ))}
          </div>

          {tab === "swap" && (
            <>
              <h1>Swap</h1>
              <p className="sub">Trade tokens on GembaBlockchain via GembaSwap.</p>
              <SwapForm />
            </>
          )}
          {tab === "liquidity" && (
            <>
              <h1>Liquidity</h1>
              <p className="sub">Add or remove GMB / token liquidity. Supports fee-on-transfer tokens.</p>
              <LiquidityForm />
            </>
          )}
          {tab === "lock" && (
            <>
              <h1>Lock LP</h1>
              <p className="sub">Time-lock LP (or any ERC-20) tokens; withdraw after the unlock date.</p>
              <LockForm />
            </>
          )}
        </div>
      </main>

      <footer className="foot">
        GembaSwap · DEX on <a href="https://gembachain.io">GembaBlockchain</a> ·{" "}
        <a href="https://testnet.gembascan.io">GembaScan</a>
        <div style={{ marginTop: 6, fontSize: 12 }}>Testnet — tokens have no monetary value.</div>
      </footer>
    </>
  );
}
