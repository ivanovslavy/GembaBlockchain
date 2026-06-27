// Central config — one NETWORK switch drives testnet today and mainnet later (same code).
import 'dotenv/config';

const NETWORK = (process.env.NETWORK || 'testnet').toLowerCase();
const isMainnet = NETWORK === 'mainnet';

export const cfg = {
  NETWORK,
  LABEL: NETWORK.toUpperCase(), // TESTNET / MAINNET — shown in every email subject + body

  // ---- chain endpoints ----
  chainId: Number(process.env.GEMBA_CHAIN_ID || (isMainnet ? 0 : 821207)),
  cosmosChainId: process.env.COSMOS_CHAIN_ID || (isMainnet ? 'gemba-1' : 'gemba-testnet-1'),
  evmRpc: process.env.EVM_RPC || 'https://rpc1.gembascan.io',
  // Cosmos REST for validator/slashing/pool — reachable only via the .162→archive(.137):1317
  // whitelist (Option A). 1317 is firewalled to the public; open it to the notifier host only.
  cosmosRest: process.env.COSMOS_REST || 'http://13.140.148.137:1317',
  explorer: process.env.EXPLORER_URL || 'https://testnet.gembascan.io',
  uptimeUrls: (process.env.UPTIME_URLS ||
    'https://rpc1.gembascan.io,https://rpc2.gembascan.io,https://rpc3.gembascan.io,https://testnet.gembascan.io')
    .split(',').map((s) => s.trim()).filter(Boolean),
  denom: process.env.DENOM || 'agmb',

  // ---- watched contract: the GembaPay GMB dispenser (its Dispensed event = "GMB sold") ----
  dispenser: (process.env.GEMBA_DISPENSER_ADDRESS || '0x0EB298466F862E548d2416a75d3D108E503bD2Cf').toLowerCase(),

  // non-voting reserves excluded from "circulating" for the bonded-ratio KPI (§3.4)
  reserves: (process.env.RESERVE_ADDRESSES ||
    'cosmos1s32mhm7c0eest48njscsr5fnn2c42mr9w8cnqe,cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d')
    .split(',').map((s) => s.trim()).filter(Boolean),

  // ---- polling ----
  pollMs: Number(process.env.POLL_MS || 30_000),       // chain watchers
  uptimePollMs: Number(process.env.UPTIME_POLL_MS || 120_000),

  // ---- SMTP (pending: domain + mailboxes are being created) ----
  smtp: {
    host: process.env.SMTP_HOST || '',
    port: Number(process.env.SMTP_PORT || 587),
    user: process.env.SMTP_USER || '',
    pass: process.env.SMTP_PASS || '',
    // sender encodes the environment; recipient is the monitored mailbox
    from: process.env.MAIL_FROM || `${NETWORK}@gembachain.io`,
    to: process.env.MAIL_TO || 'contacts@gembachain.io',
  },

  // ---- alarm thresholds (mathematically grounded — see docs/notifications-implementation-plan.md)
  thresholds: {
    validatorShareWarn: Number(process.env.TH_VAL_SHARE_WARN || 0.30),   // approaching the 1/3 halt line
    validatorShareCrit: Number(process.env.TH_VAL_SHARE_CRIT || 0.3334), // ≥1/3: one validator can halt
    minValidators: Number(process.env.TH_MIN_VALIDATORS || 4),           // BFT N≥3f+1: below 4 = critical
    bondedRatioWarn: Number(process.env.TH_BONDED_WARN || 0.50),
    bondedRatioCrit: Number(process.env.TH_BONDED_CRIT || 0.33),
    largeSaleFracBondedWarn: Number(process.env.TH_SALE_FRAC_WARN || 0.10), // sale > 10% of bonded
    largeSaleFracBondedCrit: Number(process.env.TH_SALE_FRAC_CRIT || 0.25), // sale > 25% of bonded (S>B/2 danger)
    shareRisePP7d: Number(process.env.TH_SHARE_RISE_PP || 5),            // +5pp share in 7d
    bondedDropPP7d: Number(process.env.TH_BONDED_DROP_PP || 10),         // -10pp bonded ratio in 7d
  },

  // dry-run when no SMTP configured: log instead of send (so the service is testable pre-SMTP)
  dryRun: process.env.DRY_RUN === '1' || !process.env.SMTP_HOST,

  stateFile: process.env.STATE_FILE || new URL('../data/state.json', import.meta.url).pathname,
};
