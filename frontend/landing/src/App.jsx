import { useState, useEffect, useCallback, useRef } from "react";
import "./App.css";
import NodeField from "./NodeField.jsx";

const NET = {
  name: "GembaBlockchain Testnet",
  cosmosId: "gemba-testnet-1",
  chainIdHex: "0xc87d7", // 821207
  chainId: 821207,
  rpc: "https://rpc1.gembascan.io",
  explorer: "https://testnet.gembascan.io",
  github: "https://github.com/ivanovslavy/GembaBlockchain",
  swap: "https://swap.gembachain.io",
  addresses: "https://addresses.gembachain.io",
  docs: "https://github.com/ivanovslavy/GembaBlockchain/tree/main/docs",
  gembait: "https://gembait.com",
  symbol: "GMB",
};

// Single system faucet (2026-06-27): the combo faucet dispenses BOTH native GMB and the
// test stablecoins (USDT/USDC/EURC) from one contract, with on-chain per-asset 24h cooldowns.
// One faucet for everything is simpler than scattered per-asset/per-dApp faucets. educhain
// keeps its own whitelist faucet; the 30M public reserve stays in the Cosmos faucet module.
const FAUCET = "0x0147581e2351dD182edD651DFEfD955CB353f8aA"; // combo faucet — GMB + test stablecoins
const TOKENS = [
  { symbol: "USDT", name: "Tether USD (Test)", address: "0xF61647866ad7be8137230Ad688092D2f3F4A1666", decimals: 6 },
  { symbol: "USDC", name: "USD Coin (Test)", address: "0xc9af98AD8ae78086620821F9Ceb05842Dd7950CF", decimals: 6 },
  { symbol: "EURC", name: "Euro Coin (Test)", address: "0x7Ff43282d7939418a3f0A308E2d48Dd93536044e", decimals: 6 },
];
const SEL = { claimGMB: "0xc89830b0", claimToken: "0x32f289cf" };
const SELR = { gmbAvailableAt: "0x4a1303cb", tokenAvailableAt: "0x9de4bd3d" };
const pad32 = (a) => a.toLowerCase().replace("0x", "").padStart(64, "0");

async function addToMetaMask() {
  if (!window.ethereum) {
    window.open("https://metamask.io/download/", "_blank", "noopener");
    return;
  }
  try {
    await window.ethereum.request({
      method: "wallet_addEthereumChain",
      params: [
        {
          chainId: NET.chainIdHex,
          chainName: NET.name,
          rpcUrls: [NET.rpc, "https://rpc2.gembascan.io", "https://rpc3.gembascan.io"],
          nativeCurrency: { name: "Gemba", symbol: NET.symbol, decimals: 18 },
          blockExplorerUrls: [NET.explorer],
        },
      ],
    });
  } catch (e) {
    console.error(e);
  }
}

async function ensureGembaChain() {
  try {
    await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: NET.chainIdHex }] });
  } catch (e) {
    if (e.code === 4902) await addToMetaMask();
    else throw e;
  }
}

async function sendFaucetTx(data) {
  if (!window.ethereum) { window.open("https://metamask.io/download/", "_blank", "noopener"); return; }
  try {
    const [from] = await window.ethereum.request({ method: "eth_requestAccounts" });
    await ensureGembaChain();
    await window.ethereum.request({ method: "eth_sendTransaction", params: [{ from, to: FAUCET, data }] });
  } catch (e) {
    // T-2: never surface raw provider/RPC error text to the user (it can leak RPC URLs / internal strings).
    // Log the detail to the console for debugging and show a friendly, generic message.
    console.error(e);
    alert("Transaction failed — please try again or check your wallet.");
  }
}

const claimGMB = () => sendFaucetTx(SEL.claimGMB);
const claimToken = (addr) => sendFaucetTx(SEL.claimToken + addr.toLowerCase().replace("0x", "").padStart(64, "0"));

async function addToken(tok) {
  if (!window.ethereum) { window.open("https://metamask.io/download/", "_blank", "noopener"); return; }
  try {
    await window.ethereum.request({
      method: "wallet_watchAsset",
      params: { type: "ERC20", options: { address: tok.address, symbol: tok.symbol, decimals: tok.decimals } },
    });
  } catch (e) {
    console.error(e);
  }
}

function AssetRow({ label, address, onAdd }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(address);
      setCopied(true);
      setTimeout(() => setCopied(false), 1300);
    } catch {
      /* clipboard unavailable */
    }
  };
  const short = `${address.slice(0, 6)}…${address.slice(-4)}`;
  return (
    <div className="asset">
      <span className="asset-label">{label}</span>
      <a
        className="asset-addr"
        href={`${NET.explorer}/address/${address}`}
        target="_blank"
        rel="noopener"
        title={address}
      >
        {short}
      </a>
      <div className="asset-actions">
        <button className="btn btn-sm btn-ghost" onClick={copy} aria-label={`Copy ${label} address`}>
          {copied ? "Copied ✓" : "Copy"}
        </button>
        {onAdd && (
          <button className="btn btn-sm" onClick={onAdd}>
            + MetaMask
          </button>
        )}
      </div>
    </div>
  );
}

function ClaimButtons() {
  const [avail, setAvail] = useState({});
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  const [busy, setBusy] = useState("");

  useEffect(() => {
    const id = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(id);
  }, []);

  // Read the per-wallet cooldowns via the wallet's own provider (raw eth_call, no deps).
  const refresh = useCallback(async () => {
    if (!window.ethereum) return;
    try {
      const accs = await window.ethereum.request({ method: "eth_accounts" });
      const acct = accs && accs[0];
      const chain = await window.ethereum.request({ method: "eth_chainId" });
      if (!acct || chain !== NET.chainIdHex) { setAvail({}); return; }
      const call = async (data) => {
        const r = await window.ethereum.request({ method: "eth_call", params: [{ to: FAUCET, data }, "latest"] });
        return parseInt(r, 16) || 0;
      };
      const next = { GMB: await call(SELR.gmbAvailableAt + pad32(acct)) };
      for (const t of TOKENS) next[t.symbol] = await call(SELR.tokenAvailableAt + pad32(acct) + pad32(t.address));
      setAvail(next);
    } catch (e) { /* not connected / wrong chain */ }
  }, []);

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 15000);
    const eth = window.ethereum;
    if (eth && eth.on) { eth.on("accountsChanged", refresh); eth.on("chainChanged", refresh); }
    return () => {
      clearInterval(id);
      if (eth && eth.removeListener) { eth.removeListener("accountsChanged", refresh); eth.removeListener("chainChanged", refresh); }
    };
  }, [refresh]);

  const countdown = (ts) => {
    if (!ts || ts <= now) return null;
    const s = ts - now;
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    return h > 0 ? `${h}h ${m}m` : m > 0 ? `${m}m ${sec}s` : `${sec}s`;
  };

  const doClaim = async (key, data) => {
    setBusy(key);
    try { await sendFaucetTx(data); } finally { setBusy(""); }
    setTimeout(refresh, 2000);
    setTimeout(refresh, 5000);
  };

  const gmbCd = countdown(avail.GMB);
  return (
    <div className="cta">
      <button className="btn" disabled={busy === "GMB" || !!gmbCd} onClick={() => doClaim("GMB", SEL.claimGMB)}>
        {busy === "GMB" ? "…" : gmbCd ? `0.1 GMB · ${gmbCd}` : "Claim 0.1 GMB"}
      </button>
      {TOKENS.map((t) => {
        const cd = countdown(avail[t.symbol]);
        return (
          <button className="btn" key={t.symbol} disabled={busy === t.symbol || !!cd}
            onClick={() => doClaim(t.symbol, SEL.claimToken + pad32(t.address))}>
            {busy === t.symbol ? "…" : cd ? `10,000 ${t.symbol} · ${cd}` : `Claim 10,000 ${t.symbol}`}
          </button>
        );
      })}
    </div>
  );
}

function BuyGmb() {
  const [conf, setConf] = useState({ pricePerGmbEur: 0.1, minGmb: 10, maxGmb: 10000 });
  const [addr, setAddr] = useState("");
  const [gmb, setGmb] = useState(100);
  const [phase, setPhase] = useState("form"); // form | creating | awaiting | success
  const [formErr, setFormErr] = useState("");
  const [txHash, setTxHash] = useState("");
  const [boughtGmb, setBoughtGmb] = useState(0);
  const pollRef = useRef(null);

  useEffect(() => {
    fetch("/api/purchase/config").then((r) => r.json()).then((c) => c && setConf(c)).catch(() => {});
    return () => clearInterval(pollRef.current);
  }, []);

  const eur = (Number(gmb) * (conf.pricePerGmbEur || 0) || 0).toFixed(2);
  const isAddr = /^0x[a-fA-F0-9]{40}$/.test(addr.trim());
  const valid = isAddr && Number(gmb) >= conf.minGmb && Number(gmb) <= conf.maxGmb;

  const poll = (oid) => {
    clearInterval(pollRef.current);
    pollRef.current = setInterval(async () => {
      try {
        const r = await fetch(`/api/purchase/status/${oid}`);
        const j = await r.json();
        if (j.ok && j.status === "fulfilled") {
          clearInterval(pollRef.current);
          setTxHash(j.txHash || "");
          setBoughtGmb(j.gmb || 0);
          setPhase("success");
        }
      } catch { /* keep polling */ }
    }, 4000);
  };

  const buy = async () => {
    setFormErr("");
    if (!valid) { setFormErr("Enter a valid 0x… address and an amount within range."); return; }
    setPhase("creating");
    try {
      const r = await fetch("/api/purchase/create", {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ evmAddress: addr.trim(), gmbAmount: Number(gmb) }),
      });
      const j = await r.json().catch(() => ({}));
      if (j.ok && j.checkoutUrl) {
        window.open(j.checkoutUrl, "_blank", "noopener,noreferrer");
        setPhase("awaiting");
        poll(j.orderId);
      } else { setPhase("form"); setFormErr("Couldn't start checkout — please try again."); }
    } catch { setPhase("form"); setFormErr("Couldn't start checkout — please try again."); }
  };

  const close = () => { clearInterval(pollRef.current); setPhase("form"); setTxHash(""); };

  return (
    <div className="contact-form">
      <label className="buy-label">Your GembaBlockchain (EVM) address — GMB is sent here</label>
      <input placeholder="0x…" value={addr} onChange={(e) => setAddr(e.target.value)} maxLength={42} spellCheck="false" />
      <div className="contact-row">
        <div>
          <label className="buy-label">Amount of GMB</label>
          <input type="number" min={conf.minGmb} max={conf.maxGmb} step="1" value={gmb} onChange={(e) => setGmb(e.target.value)} />
        </div>
        <div>
          <label className="buy-label">You pay</label>
          <input value={`€ ${eur}`} readOnly tabIndex={-1} style={{ opacity: 0.85 }} />
        </div>
      </div>
      <button className="btn" disabled={phase === "creating"} onClick={buy}>
        {phase === "creating" ? "Opening checkout…" : "Pay with GembaPay"}
      </button>
      <p className="form-msg muted" style={{ color: "var(--text-tertiary)" }}>
        {conf.minGmb}–{conf.maxGmb} GMB · pay by card or crypto via GembaPay · GMB is delivered to your
        address automatically once payment is confirmed.
      </p>
      {formErr && <p className="form-msg err">{formErr}</p>}

      {(phase === "awaiting" || phase === "success") && (
        <div className="pay-overlay" role="dialog" aria-modal="true">
          <div className={`pay-card ${phase === "success" ? "ok" : ""}`}>
            <button className="pay-close" onClick={close} aria-label="Close">×</button>
            {phase === "awaiting" ? (
              <>
                <div className="pay-spinner" />
                <h3>Awaiting payment…</h3>
                <p>Complete your payment in the new tab. Your GMB is delivered automatically once payment
                is confirmed — keep this window open.</p>
              </>
            ) : (
              <>
                <div className="pay-check">
                  <svg viewBox="0 0 52 52"><circle cx="26" cy="26" r="24" fill="none" /><path fill="none" d="M14 27l8 8 16-16" /></svg>
                </div>
                <h3>Payment successful</h3>
                <p>{boughtGmb ? `${Number(boughtGmb).toLocaleString("en-US")} GMB` : "Your GMB"} has been sent to your address.</p>
                {txHash && <a className="btn" href={`${NET.explorer}/tx/${txHash}`} target="_blank" rel="noopener">View GMB transfer ↗</a>}
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

const TURNSTILE_SITEKEY = "0x4AAAAAADr41oPreDMPGC0C";

function ContactForm() {
  const [f, setF] = useState({ name: "", email: "", subject: "", message: "" });
  const [token, setToken] = useState("");
  const [status, setStatus] = useState(""); // "" | sending | ok | error | invalid | captcha
  const widgetRef = useRef(null);
  const widgetId = useRef(null);

  useEffect(() => {
    let cancelled = false;
    const render = () => {
      if (cancelled) return;
      if (window.turnstile && widgetRef.current && widgetId.current === null) {
        widgetId.current = window.turnstile.render(widgetRef.current, {
          sitekey: TURNSTILE_SITEKEY,
          callback: (t) => setToken(t),
          "error-callback": () => setToken(""),
          "expired-callback": () => setToken(""),
        });
      } else if (!window.turnstile) {
        setTimeout(render, 300);
      }
    };
    render();
    return () => { cancelled = true; };
  }, []);

  const onChange = (e) => setF((s) => ({ ...s, [e.target.name]: e.target.value }));
  const resetCaptcha = () => {
    if (window.turnstile && widgetId.current !== null) window.turnstile.reset(widgetId.current);
    setToken("");
  };

  const submit = async (e) => {
    e.preventDefault();
    if (!f.name.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.email) || !f.message.trim()) {
      setStatus("invalid"); return;
    }
    if (!token) { setStatus("captcha"); return; }
    setStatus("sending");
    try {
      const r = await fetch("/api/contact", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...f, token }),
      });
      const j = await r.json().catch(() => ({}));
      if (r.ok && j.ok) { setStatus("ok"); setF({ name: "", email: "", subject: "", message: "" }); }
      else setStatus("error");
    } catch { setStatus("error"); }
    resetCaptcha();
  };

  return (
    <form className="contact-form" onSubmit={submit}>
      <div className="contact-row">
        <input name="name" placeholder="Your name" value={f.name} onChange={onChange} maxLength={120} required />
        <input name="email" type="email" placeholder="Your email" value={f.email} onChange={onChange} maxLength={160} required />
      </div>
      <input name="subject" placeholder="Subject (optional)" value={f.subject} onChange={onChange} maxLength={160} />
      <textarea name="message" placeholder="Your message" rows={5} value={f.message} onChange={onChange} maxLength={5000} required />
      <div className="turnstile-wrap"><div ref={widgetRef} /></div>
      <button className="btn" type="submit" disabled={status === "sending"}>
        {status === "sending" ? "Sending…" : "Send message"}
      </button>
      {status === "ok" && <p className="form-msg ok">Thanks — your message was sent. We emailed you a copy.</p>}
      {status === "error" && <p className="form-msg err">Something went wrong — please try again.</p>}
      {status === "invalid" && <p className="form-msg err">Please fill in your name, a valid email and a message.</p>}
      {status === "captcha" && <p className="form-msg err">Please complete the verification below the message.</p>}
    </form>
  );
}

const FEATURES = [
  {
    title: "Permissionless PoS",
    body: "CometBFT BFT Proof-of-Stake — ~5s blocks with instant finality (no reorgs). Anyone with enough stake can validate — no operator approves participants, no KYC, no whitelist.",
  },
  {
    title: "Full EVM",
    body: "Solidity, MetaMask, Foundry/Hardhat, ethers/viem and standard 0x addresses. Build and deploy exactly like on Ethereum, over EVM JSON-RPC.",
  },
  {
    title: "Fixed supply, 0% inflation",
    body: "GMB is minted once at genesis and never again. Validator rewards come from a pre-minted reserve, not new issuance — no dilution.",
  },
  {
    title: "Utility, never speculation",
    body: "By design GembaBlockchain provides no liquidity for GMB and operates no exchange. It is not built for speculation or trading — GMB exists to be used (service access, access control, tickets, perks), not bought and sold.",
  },
  {
    title: "Founder holds no power",
    body: "The founder wallet is a non-voting treasury. No privileged validators, no admin key over reserves — funds move only via governance + timelock.",
  },
  {
    title: "For society & institutions",
    body: "Created for the good of society — for public institutions and private organizations to integrate the chain and deliver services to their citizens and users, all under the same on-chain rules.",
  },
];

const DETAILS = [
  ["Network", "GembaBlockchain testnet"],
  ["Cosmos chain-id", NET.cosmosId],
  ["EVM chainId", String(NET.chainId)],
  ["Currency symbol", NET.symbol],
  ["RPC URL", NET.rpc],
  ["Block explorer", NET.explorer],
];

function App() {
  return (
    <>
      <div className="nodefield-bg"><NodeField /></div>
      <div className="page">
      <header className="nav">
        <a className="brand" href="/">
          <img src="/gemba-animated.svg" alt="" width="34" height="34" />
          <span>
            Gemba<b>Blockchain</b>
          </span>
        </a>
        <nav className="nav-links">
          <a href={NET.swap} target="_blank" rel="noopener">
            Swap
          </a>
          <a href="#faucet">Faucet</a>
          <a href="#buy">Buy GMB</a>
          <a href={NET.explorer} target="_blank" rel="noopener">
            Explorer
          </a>
          <a href={NET.addresses} target="_blank" rel="noopener">
            Addresses
          </a>
          <a href={NET.docs} target="_blank" rel="noopener">
            Docs
          </a>
          <a href="#contact">Contact</a>
          <a href={NET.github} target="_blank" rel="noopener">
            GitHub
          </a>
        </nav>
      </header>

      <main>
        <section className="hero">
          <img className="hero-logo" src="/gemba-animated.svg" alt="GembaBlockchain" />
          <div className="badge">Live testnet · Bulgaria's first blockchain</div>
          <h1>
            Bulgaria's first blockchain —
            <br />
            <span className="grad">built for society, not speculation</span>
          </h1>
          <p className="lede">
            GembaBlockchain is a sovereign, public, permissionless Cosmos EVM PoS L1 —
            <strong> the first blockchain built in Bulgaria</strong>. Its native coin
            <strong> Gemba (GMB)</strong> is a pure utility coin: cheaper service access,
            workplace access control, tickets and perks. <strong>By design no liquidity
            is provided for GMB and we operate no exchange</strong> — the chain is not
            made for speculation or trading. It exists for the good of society: for
            public institutions and private organizations to integrate it and deliver
            services to their citizens and users.
          </p>
          <div className="cta">
            <a className="btn" href={NET.explorer} target="_blank" rel="noopener">Open GembaScan</a>
            <a className="btn" href={NET.github} target="_blank" rel="noopener">View on GitHub</a>
          </div>
          <div className="credit">
            Created by{" "}
            <a href={NET.gembait} target="_blank" rel="noopener"><b>GembaIT studio</b></a>
            <span className="role">Lead: Slavcho Ivanov — 20-year Linux engineer &amp; blockchain architect</span>
          </div>
        </section>

        <section className="appblock">
          <div className="txt">
            <h2>GembaSwap — the ecosystem DEX</h2>
            <p>
              Our own app on GembaBlockchain: <strong>swap tokens</strong>, wrap{" "}
              <strong>GMB ↔ WGMB (1:1)</strong>, <strong>add &amp; remove liquidity</strong>{" "}
              (including fee-on-transfer tokens), and <strong>lock / unlock LP tokens</strong>. No
              platform fees — we take no cut. Gas is near-zero (~1 gwei).
            </p>
            <div className="feats">
              <span>Swap</span>
              <span>Wrap / Unwrap</span>
              <span>Add / Remove liquidity</span>
              <span>Fee-on-transfer</span>
              <span>Lock / Unlock LP</span>
            </div>
          </div>
        </section>

        <section className="features">
          {FEATURES.map((f) => (
            <article className="card" key={f.title}>
              <h3>{f.title}</h3>
              <p>{f.body}</p>
            </article>
          ))}
        </section>

        <section className="details">
          <div className="details-inner">
            <h2>Connect to the testnet</h2>
            <p className="muted">
              Standard <code>0x…</code> addresses (eth_secp256k1, coin type 60) —
              MetaMask works out of the box.
            </p>
            <table>
              <tbody>
                {DETAILS.map(([k, v]) => (
                  <tr key={k}>
                    <th>{k}</th>
                    <td>{v}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <button className="btn" onClick={addToMetaMask}>
              Add GembaBlockchain to MetaMask
            </button>

            <div className="registries">
              <p className="muted">
                Listed in the public chain registries that wallets and explorers
                read — both pull requests merged. The <strong>testnet</strong> is
                recognized network-wide, so{" "}
                <a href="https://chainlist.org" target="_blank" rel="noopener">
                  chainlist.org
                </a>{" "}
                adds it to MetaMask in one click:
              </p>
              <div className="registry-badges" style={{ justifyContent: "center" }}>
                <a
                  className="btn btn-sm"
                  href="https://github.com/ethereum-lists/chains/pull/8413"
                  target="_blank"
                  rel="noopener"
                >
                  ethereum-lists/chains
                </a>
                <a
                  className="btn btn-sm"
                  href="https://github.com/blockscout/chainscout/pull/241"
                  target="_blank"
                  rel="noopener"
                >
                  Blockscout chainscout
                </a>
              </div>
              <p className="muted registries-note">
                Testnet listing (EVM chainId 821207). Mainnet (821206) is not yet
                launched and gets its own registry entries later.
              </p>
            </div>
          </div>
        </section>

        <section className="details" id="faucet">
          <div className="details-inner">
            <h2>Testnet faucet &amp; test stablecoins</h2>
            <p className="muted">
              Free testnet assets so anyone can try GembaBlockchain and the dApps built on it.
              Per wallet: <strong>0.1 GMB</strong> and <strong>10,000 of each stablecoin</strong>{" "}
              every 24 hours. These are valueless test tokens — not real USDT / USDC / EURC.
            </p>
            <ClaimButtons />
            <div className="assets">
              <AssetRow label="Faucet" address={FAUCET} />
              {TOKENS.map((t) => (
                <AssetRow key={t.symbol} label={t.symbol} address={t.address} onAdd={() => addToken(t)} />
              ))}
            </div>
            <p className="muted registries-note">
              The faucet is also built into the dApps with a full UI and cooldown timers:{" "}
              <a href="https://win.gembait.com/en/faucet" target="_blank" rel="noopener">GembaWin faucet</a>
              {" · "}
              <a href="https://escrow.gembait.com/en/faucet" target="_blank" rel="noopener">GembaEscrow faucet</a>.
              Stablecoins are minted on demand; the native GMB reserve has a global daily cap, so a
              sybil swarm can never drain it.
            </p>
          </div>
        </section>

        <section className="details" id="buy">
          <div className="details-inner">
            <h2>Buy GMB</h2>
            <p className="muted">
              Get GMB delivered straight to your wallet. Pay by card or crypto through
              <strong> GembaPay</strong>; once the payment is confirmed, GMB is sent automatically
              to the address you provide. (Testnet GMB has no monetary value — this is the same flow
              that will run on mainnet.)
            </p>
            <BuyGmb />
          </div>
        </section>

        <section className="details" id="contact">
          <div className="details-inner">
            <h2>Get in touch</h2>
            <p className="muted">
              Questions about GembaBlockchain, running a validator, or integrating the chain?
              Send us a message — you'll get a copy by email.
            </p>
            <ContactForm />
          </div>
        </section>

        <section className="note">
          <p>
            <strong>Not for speculation — by design.</strong> GembaBlockchain provides
            no liquidity for GMB, runs no exchange and does not redeem GMB for fiat. It
            is infrastructure for institutions and organizations to serve people, not a
            tradable asset. <code>gemba-testnet-1</code> is a valueless public test
            network — a mainnet dress rehearsal. The chain is permissionless by rule and
            decentralizing over time; the public mainnet is gated by an independent
            security audit.
          </p>
        </section>
      </main>

      <footer className="footer">
        <div className="footer-brand">
          <img src="/gemba-animated.svg" alt="" width="26" height="26" />
          <span>
            Gemba<b>Blockchain</b>
          </span>
        </div>
        <nav className="footer-links">
          <a href={NET.swap} target="_blank" rel="noopener">
            Swap
          </a>
          <a href="#faucet">Faucet</a>
          <a href="#buy">Buy GMB</a>
          <a href={NET.explorer} target="_blank" rel="noopener">
            Explorer
          </a>
          <a href={`${NET.explorer}/rpc`} target="_blank" rel="noopener">
            RPC
          </a>
          <a href={NET.addresses} target="_blank" rel="noopener">
            Addresses
          </a>
          <a href={NET.docs} target="_blank" rel="noopener">
            Docs
          </a>
          <a href="#contact">Contact</a>
          <a href={NET.github} target="_blank" rel="noopener">
            GitHub
          </a>
        </nav>
        <p className="legal-links">
          <a href="/terms/">Terms of Service</a> · <a href="/privacy/">Privacy Policy</a>
        </p>
        <p className="copy">
          GembaBlockchain · Bulgaria's first blockchain · public decentralized PoS L1 ·
          built for society, not speculation
        </p>
      </footer>
    </div>
    </>
  );
}

export default App;
