import ConnectButton from "./components/ConnectButton.jsx";
import SwapForm from "./components/SwapForm.jsx";

export default function App() {
  return (
    <>
      <header className="topbar">
        <a className="brand" href="https://gembachain.io"><span className="dot" /> Gemba<span className="gradient">Swap</span></a>
        <ConnectButton />
      </header>

      <main className="wrap">
        <div className="card">
          <h1>Swap</h1>
          <p className="sub">Trade tokens on GembaBlockchain via the GembaSwap DEX.</p>
          <SwapForm />
        </div>
      </main>

      <footer className="foot">
        GembaSwap · DEX on <a href="https://gembachain.io">GembaBlockchain</a> ·
        explorer <a href="https://testnet.gembascan.io">GembaScan</a>
        <div style={{ marginTop: 6, fontSize: 12 }}>Testnet — tokens have no monetary value.</div>
      </footer>
    </>
  );
}
