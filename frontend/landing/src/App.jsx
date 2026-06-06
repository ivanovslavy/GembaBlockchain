import "./App.css";

const NET = {
  name: "GembaBlockchain Testnet",
  cosmosId: "gemba-testnet-1",
  chainIdHex: "0xc87d7", // 821207
  chainId: 821207,
  rpc: "https://testnet.gembascan.io/rpc",
  explorer: "https://testnet.gembascan.io",
  github: "https://github.com/ivanovslavy/GembaBlockchain",
  symbol: "GMB",
};

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

const FEATURES = [
  {
    title: "Permissionless PoS",
    body: "CometBFT BFT Proof-of-Stake with ~2s instant finality. Anyone with enough stake can validate — no operator approves participants, no KYC, no whitelist.",
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
          <img src="/gemba-symbol.svg" alt="" width="34" height="34" />
          <span>
            Gemba<b>Blockchain</b>
          </span>
        </a>
        <nav className="nav-links">
          <a href={NET.explorer} target="_blank" rel="noopener">
            Explorer
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
          <img className="hero-logo" src="/gemba-symbol.svg" alt="GembaBlockchain" />
          <div className="badge">🇧🇬 Bulgaria's first blockchain · Live testnet</div>
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
            <button className="btn btn-primary" onClick={addToMetaMask}>
              Add to MetaMask
            </button>
            <a className="btn" href={NET.explorer} target="_blank" rel="noopener">
              Open GembaScan
            </a>
            <a className="btn btn-ghost" href={NET.github} target="_blank" rel="noopener">
              View on GitHub
            </a>
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
            <button className="btn btn-primary" onClick={addToMetaMask}>
              Add GembaBlockchain to MetaMask
            </button>
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
          <img src="/gemba-symbol.svg" alt="" width="26" height="26" />
          <span>
            Gemba<b>Blockchain</b>
          </span>
        </div>
        <nav className="footer-links">
          <a href={NET.explorer} target="_blank" rel="noopener">
            Explorer
          </a>
          <a href={`${NET.explorer}/rpc`} target="_blank" rel="noopener">
            RPC
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
