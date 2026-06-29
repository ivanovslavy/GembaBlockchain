import { JsonRpcProvider, WebSocketProvider, Network } from "ethers";

// Round-robin over multiple RPC endpoints so we also spread the *ingestion* load
// across nodes (consensus already involves all validators via P2P).
export function makeProviders(urls, chainId) {
  const net = Network.from(Number(chainId));
  const providers = urls.map(
    (u) => new JsonRpcProvider(u.trim(), net, { staticNetwork: net, batchMaxCount: 1 })
  );
  let i = 0;
  return {
    all: providers,
    next: () => providers[i++ % providers.length],
    primary: providers[0],
  };
}

export function makeWs(url) {
  if (!url) return null;
  try { return new WebSocketProvider(url); } catch { return null; }
}
