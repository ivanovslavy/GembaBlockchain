// Endurance profile: a short ramp, then ~24h of LOW, CONSTANT, varied activity. The goal is
// realism + 0 reverts / 99.9%+ mined over a full day — NOT peak TPS. Everything is env-tunable
// so the same code runs the 10-min dry-run (STEADY_SEC=480) and the 24h run (STEADY_SEC=86400).
export function buildProfile(name, env) {
  const TPS = Number(env.TARGET_TPS || 4);                 // steady rate (3–6 is the sweet spot)
  const RAMP_SEC = Number(env.RAMP_SEC || 300);            // warm the guards up gently
  const STEADY_SEC = Number(env.STEADY_SEC || 86400);      // 24h
  const START_TPS = Number(env.START_TPS || 1);
  // Concurrency is the max parallel in-flight submits. At a few TPS this is tiny; keep it low
  // so we never burst the rate-limited public RPCs.
  const C = (d) => Number(env.CONCURRENCY) || d;

  switch (name) {
    case "ENDURANCE":
      return {
        name: "ENDURANCE", mode: "phases", weights: "endurance", concurrency: C(20),
        phases: [
          { name: "ramp", fromTps: START_TPS, toTps: TPS, durationSec: RAMP_SEC },
          { name: "steady", tps: TPS, durationSec: STEADY_SEC },
        ],
      };
    default:
      throw new Error(`unknown profile ${name} (use ENDURANCE)`);
  }
}
