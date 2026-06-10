import "./App.css";

const NET = {
  name: "GembaBlockchain Testnet",
  cosmosId: "gemba-testnet-1",
  chainIdHex: "0xc87d7", // 821207
  chainId: 821207,
  rpc: "https://testnet.gembascan.io/rpc",
  explorer: "https://testnet.gembascan.io",
  github: "https://github.com/ivanovslavy/GembaBlockchain",
  swap: "https://swap.gembachain.io",
  addresses: "https://addresses.gembachain.io",
  gembait: "https://gembait.com",
  symbol: "GMB",
};

const FAUCET = "0x2baE94C0463bcdcCD0120A33D90E7fB5b5449584";
const TOKENS = [
  { symbol: "USDT", name: "Tether USD (Test)", address: "0x0821EAAE0328b02d6f85C36925acb92E90ef680C", decimals: 6 },
  { symbol: "USDC", name: "USD Coin (Test)", address: "0x131f3087ecabA6f7ae91439DDaF70f4269D4b9Ef", decimals: 6 },
  { symbol: "EURC", name: "Euro Coin (Test)", address: "0x05003C73FfEC1c2f56021549501Dd7AD850e39C3", decimals: 6 },
];
const SEL = { claimGMB: "0xc89830b0", claimToken: "0x32f289cf" };

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
          rpcUrls: [NET.rpc],
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
    console.error(e);
    alert(e?.data?.message || e?.shortMessage || e?.message || "Transaction failed");
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
    <div className="page">
      <header className="nav">
        <a className="brand" href="/">
          <img src="/gemba-animated.svg" alt="" width="34" height="34" />
          <span>
            Gemba<b>Blockchain</b>
          </span>
        </a>
        <nav className="nav-links">
          <a className="btn btn-sm" href={NET.swap} target="_blank" rel="noopener">
            Swap
          </a>
          <a href="#faucet">Faucet</a>
          <a href={NET.explorer} target="_blank" rel="noopener">
            Explorer
          </a>
          <a href={NET.addresses} target="_blank" rel="noopener">
            Addresses
          </a>
          <a href={NET.github} target="_blank" rel="noopener">
            GitHub
          </a>
          <button className="btn btn-sm" onClick={addToMetaMask}>
            Add to MetaMask
          </button>
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
            <button className="btn" onClick={addToMetaMask}>Add to MetaMask</button>
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
          <a className="btn" href={NET.swap} target="_blank" rel="noopener">Open GembaSwap →</a>
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
              <div className="registry-badges">
                <a
                  className="btn btn-sm"
                  href="https://github.com/ethereum-lists/chains/pull/8413"
                  target="_blank"
                  rel="noopener"
                >
                  ethereum-lists/chains ↗
                </a>
                <a
                  className="btn btn-sm"
                  href="https://github.com/blockscout/chainscout/pull/241"
                  target="_blank"
                  rel="noopener"
                >
                  Blockscout chainscout ↗
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
            <div className="cta">
              <button className="btn" onClick={claimGMB}>Claim 0.1 GMB</button>
              {TOKENS.map((t) => (
                <button className="btn" key={t.symbol} onClick={() => claimToken(t.address)}>
                  Claim 10,000 {t.symbol}
                </button>
              ))}
            </div>
            <table>
              <tbody>
                <tr>
                  <th>Faucet</th>
                  <td>
                    <a href={`${NET.explorer}/address/${FAUCET}`} target="_blank" rel="noopener">{FAUCET}</a>
                  </td>
                </tr>
                {TOKENS.map((t) => (
                  <tr key={t.symbol}>
                    <th>{t.symbol}</th>
                    <td>
                      <a href={`${NET.explorer}/address/${t.address}`} target="_blank" rel="noopener">{t.address}</a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <div className="registry-badges">
              {TOKENS.map((t) => (
                <button className="btn btn-sm" key={t.symbol} onClick={() => addToken(t)}>
                  Add {t.symbol} to MetaMask
                </button>
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
          <a href={NET.explorer} target="_blank" rel="noopener">
            Explorer
          </a>
          <a href={`${NET.explorer}/rpc`} target="_blank" rel="noopener">
            RPC
          </a>
          <a href={NET.addresses} target="_blank" rel="noopener">
            Addresses
          </a>
          <a href={NET.github} target="_blank" rel="noopener">
            GitHub
          </a>
        </nav>
        <p className="copy">
          GembaBlockchain · Bulgaria's first blockchain · public decentralized PoS L1 ·
          built for society, not speculation
        </p>
      </footer>
    </div>
  );
}

export default App;
