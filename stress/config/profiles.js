// Three run profiles. Block time on GembaBlockchain testnet ≈ 5.2s — latency
// thresholds are expressed in that unit. TARGET_TPS (from profile A's result) and
// SOAK_TPS are read from env so B/C can use the discovered ceiling.
export function buildProfile(name, env) {
  const TARGET = Number(env.TARGET_TPS || 50);   // set from A's knee
  const SOAK = Number(env.SOAK_TPS || Math.max(5, Math.round(TARGET * 0.4)));
  const BLOCK_MS = Number(env.BLOCK_MS || 5200);
  // Concurrency is env-tunable: on a small box that ALSO validates, 600 thrashes the CPU
  // (load >> cores) and inflates p95 — set CONCURRENCY=100-150 there so the knee reflects
  // the chain, not the generator's own context-switching.
  const C = (d) => Number(env.CONCURRENCY) || d;

  switch (name) {
    case "A": // Calibration + ramp (~30 min) — find the knee, auto-stop.
      return {
        name: "A", mode: "ramp", weights: "all", concurrency: C(600),
        warmupSec: 60, startTps: 15, stepTps: 30, stepSec: 45, maxDurationSec: 1800,
        knee: { p95Ms: 4 * BLOCK_MS, errRate: 0.15, plateauRatio: 0.7 },
      };
    case "B": // Standard (~2h): ramp → hold 80% → spike 150% → drain.
      return {
        name: "B", mode: "phases", weights: "all", concurrency: C(350),
        phases: [
          { name: "ramp", fromTps: 5, toTps: TARGET, durationSec: 300 },
          { name: "hold", tps: Math.round(TARGET * 0.8), durationSec: 6660 },
          { name: "spike", tps: Math.round(TARGET * 1.5), durationSec: 120 },
          { name: "cooldown", tps: Math.round(TARGET * 0.5), durationSec: 120 },
        ],
      };
    case "C": // Soak (~4h): steady moderate load — slow leaks, state growth, drift.
      return {
        name: "C", mode: "phases", weights: "soak", concurrency: C(200),
        phases: [
          { name: "ramp", fromTps: 5, toTps: SOAK, durationSec: 300 },
          { name: "soak", tps: SOAK, durationSec: 14100 },
        ],
      };
    default:
      throw new Error(`unknown profile ${name} (use A|B|C)`);
  }
}
