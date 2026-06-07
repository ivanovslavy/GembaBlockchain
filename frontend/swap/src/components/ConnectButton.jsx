import { useAccount, useConnect, useDisconnect, useSwitchChain, useChainId } from "wagmi";
import { DEFAULT_CHAIN_ID } from "../config/chains.js";

const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;

export default function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  const chainId = useChainId();

  if (!isConnected) {
    const injected = connectors.find((c) => c.id === "injected") || connectors[0];
    return <button className="tokbtn" disabled={isPending} onClick={() => connect({ connector: injected })}>{isPending ? "…" : "Connect Wallet"}</button>;
  }
  if (chainId !== DEFAULT_CHAIN_ID) {
    return <button className="tokbtn" onClick={() => switchChain({ chainId: DEFAULT_CHAIN_ID })}>Switch to GembaBlockchain</button>;
  }
  return <button className="tokbtn" onClick={() => disconnect()} title="Disconnect"><span className="dot" style={{ width: 8, height: 8, borderRadius: 99, background: "var(--ok)", display: "inline-block" }} /> {short(address)}</button>;
}
