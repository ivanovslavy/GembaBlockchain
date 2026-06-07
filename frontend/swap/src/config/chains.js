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
  },
  821206: { router: "", factory: "", wgmb: "" },
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
    [gembaTestnet.id]: fallback(TESTNET_RPCS.map((u) => http(u))),
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

export const NATIVE = { address: "native", symbol: "GMB", name: "Gemba", decimals: 18, isNative: true };
