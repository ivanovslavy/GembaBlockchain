import { defineChain, http, fallback } from "viem";
import { createConfig } from "wagmi";
import { injected, walletConnect } from "wagmi/connectors";

const TESTNET_RPCS = [
  "https://testnet.gembascan.io/rpc",
  "https://rpc1.gembascan.io",
  "https://rpc2.gembascan.io",
];

export const gembaTestnet = defineChain({
  id: 821207,
  name: "GembaBlockchain Testnet",
  nativeCurrency: { name: "Gemba", symbol: "GMB", decimals: 18 },
  rpcUrls: { default: { http: TESTNET_RPCS } },
  blockExplorers: { default: { name: "GembaScan", url: "https://testnet.gembascan.io" } },
  testnet: true,
});

// Mainnet (gemba-1, chainId 821206) — not live yet; DEX addresses fill in at launch.
export const gembaMainnet = defineChain({
  id: 821206,
  name: "GembaBlockchain",
  nativeCurrency: { name: "Gemba", symbol: "GMB", decimals: 18 },
  rpcUrls: { default: { http: ["https://rpc.gembachain.io"] } },
  blockExplorers: { default: { name: "GembaScan", url: "https://gembascan.io" } },
});

// GembaSwap (Uniswap V2) deployments per chain. Mainnet TBD at launch.
export const DEX = {
  821207: {
    router: "0x53D78A64D01fC38A7Cc3436b6ec81DB203836D65",
    factory: "0x61224Ee338C3c62e1050838AB75c76A7cd6f95ed",
    wgmb: "0x68b735671C0b6ab1a6B8Fe4eaBd532B8736E68b4",
    locker: "0x88CB73797FFA34d6D469e855ea19A7bB28Ba1020",
  },
  821206: { router: "", factory: "", wgmb: "", locker: "" },
};

export const SUPPORTED_CHAINS = [gembaTestnet]; // add gembaMainnet at launch
export const DEFAULT_CHAIN_ID = 821207;

const WC_PROJECT_ID = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || "";
const connectors = [injected({ shimDisconnect: true })];
if (WC_PROJECT_ID) {
  connectors.push(walletConnect({
    projectId: WC_PROJECT_ID,
    metadata: { name: "GembaSwap", description: "Swap on GembaBlockchain", url: "https://swap.gembachain.io", icons: ["https://swap.gembachain.io/favicon.svg"] },
    showQrModal: true,
  }));
}

export const wagmiConfig = createConfig({
  chains: SUPPORTED_CHAINS,
  connectors,
  transports: {
    // T-3 — RPC trust assumption (testnet read path): viem `fallback` tries the RPCs in order and the UI
    // trusts whatever the first healthy endpoint returns. There is NO cross-checking of replies between RPCs —
    // a single malicious/compromised RPC could feed the UI a wrong balance/quote/reserve. Accepted for a
    // valueless testnet read path; do not rely on it for value-critical reads without multi-RPC agreement.
    // `rank: true` makes viem actively measure latency/health and prefer the best-performing RPC.
    [gembaTestnet.id]: fallback(TESTNET_RPCS.map((u) => http(u)), { rank: true }),
  },
});

// ---- ABIs (minimal) ----
export const ROUTER_ABI = [
  { name: "WETH", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { name: "factory", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { name: "getAmountsOut", type: "function", stateMutability: "view", inputs: [{ name: "amountIn", type: "uint256" }, { name: "path", type: "address[]" }], outputs: [{ name: "amounts", type: "uint256[]" }] },
  { name: "swapExactTokensForTokens", type: "function", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint256" }, { type: "address[]" }, { type: "address" }, { type: "uint256" }], outputs: [{ type: "uint256[]" }] },
  { name: "swapExactETHForTokens", type: "function", stateMutability: "payable", inputs: [{ type: "uint256" }, { type: "address[]" }, { type: "address" }, { type: "uint256" }], outputs: [{ type: "uint256[]" }] },
  { name: "swapExactTokensForETH", type: "function", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint256" }, { type: "address[]" }, { type: "address" }, { type: "uint256" }], outputs: [{ type: "uint256[]" }] },
  { name: "quote", type: "function", stateMutability: "pure", inputs: [{ name: "amountA", type: "uint256" }, { name: "reserveA", type: "uint256" }, { name: "reserveB", type: "uint256" }], outputs: [{ type: "uint256" }] },
  // liquidity (token + native GMB, via the WGMB-backed router)
  { name: "addLiquidityETH", type: "function", stateMutability: "payable", inputs: [{ name: "token", type: "address" }, { name: "amountTokenDesired", type: "uint256" }, { name: "amountTokenMin", type: "uint256" }, { name: "amountETHMin", type: "uint256" }, { name: "to", type: "address" }, { name: "deadline", type: "uint256" }], outputs: [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }] },
  { name: "removeLiquidityETH", type: "function", stateMutability: "nonpayable", inputs: [{ name: "token", type: "address" }, { name: "liquidity", type: "uint256" }, { name: "amountTokenMin", type: "uint256" }, { name: "amountETHMin", type: "uint256" }, { name: "to", type: "address" }, { name: "deadline", type: "uint256" }], outputs: [{ type: "uint256" }, { type: "uint256" }] },
  { name: "removeLiquidityETHSupportingFeeOnTransferTokens", type: "function", stateMutability: "nonpayable", inputs: [{ name: "token", type: "address" }, { name: "liquidity", type: "uint256" }, { name: "amountTokenMin", type: "uint256" }, { name: "amountETHMin", type: "uint256" }, { name: "to", type: "address" }, { name: "deadline", type: "uint256" }], outputs: [{ type: "uint256" }] },
];

// GembaSwap pair (LP token is an ERC-20; reuse ERC20_ABI for balanceOf/approve/allowance).
export const PAIR_ABI = [
  { name: "getReserves", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint112" }, { type: "uint112" }, { type: "uint32" }] },
  { name: "token0", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { name: "token1", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { name: "totalSupply", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
];

// LiquidityLocker — lock/extend/withdraw LP (or any ERC-20) tokens.
export const LOCKER_ABI = [
  { name: "lock", type: "function", stateMutability: "nonpayable", inputs: [{ name: "token", type: "address" }, { name: "amount", type: "uint256" }, { name: "unlockTime", type: "uint64" }], outputs: [{ type: "uint256" }] },
  { name: "withdraw", type: "function", stateMutability: "nonpayable", inputs: [{ name: "lockId", type: "uint256" }], outputs: [] },
  { name: "extend", type: "function", stateMutability: "nonpayable", inputs: [{ name: "lockId", type: "uint256" }, { name: "newUnlockTime", type: "uint64" }], outputs: [] },
  { name: "getLock", type: "function", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "tuple", components: [{ name: "owner", type: "address" }, { name: "token", type: "address" }, { name: "amount", type: "uint256" }, { name: "unlockTime", type: "uint64" }, { name: "withdrawn", type: "bool" }] }] },
  { name: "userLockIds", type: "function", stateMutability: "view", inputs: [{ name: "user", type: "address" }], outputs: [{ type: "uint256[]" }] },
];
export const FACTORY_ABI = [
  { name: "getPair", type: "function", stateMutability: "view", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "address" }] },
];
export const ERC20_ABI = [
  { name: "name", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { name: "symbol", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { name: "decimals", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { name: "balanceOf", type: "function", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { name: "allowance", type: "function", stateMutability: "view", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "uint256" }] },
  { name: "approve", type: "function", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
];

export const WGMB_ABI = [
  { name: "deposit", type: "function", stateMutability: "payable", inputs: [], outputs: [] },
  { name: "withdraw", type: "function", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [] },
];

export const NATIVE = { address: "native", symbol: "GMB", name: "Gemba", decimals: 18, isNative: true };
