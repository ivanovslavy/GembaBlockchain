# Re-genesis 2026-06-06 — изпълнение, инциденти и текущо състояние

> Документ за всичко направено на 2026-06-06 по re-genesis на `gemba-testnet-1`.
> Следва стъпките от `docs/runbooks/testnet-re-genesis.md`.

---

## Какво е направено преди тази сесия (от git история)

| Commit | Съдържание |
|---|---|
| `7d0cfbc` | `init-local-testnet.sh` обновен с точните §4.1 % (30M/20M/15M/10M/10M/5M/10M); генераторът валидиран локално |
| `02d309f` | `x/valgate` wired в `gembad` — governance-tunable min self-bond (1 000 GMB) |
| `5cca9dc` | `contracts/script/DeployGovernance.s.sol` — deploy governance + reserves + fund; **тестван на local devnet**, НЕ на live testnet |
| `7a4790f` | `contracts/script/verify-all.sh` — верификация на всички CA в GembaScan |

**Важно:** стъпки 1–2 от runbook-а са завършени. Стъпки 3–9 са в процес.

---

## Стъпка 3 — Reset и рестарт на validator-ите (изпълнено)

Re-genesis-ът е извършен от оператора ПРЕДИ тази сесия:
- Всичките 4 validator-а са получили нов `genesis.json` (md5 `24fbb82caf457cd613a612c366927b14`, genesis_time `2026-06-06T08:46:42Z`)
- Услугите са рестартирани в ~11:19 CEST (09:19 UTC)
- Старата верига (height 18 340) е прекратена

---

## Инциденти открити при старта на новата верига

### Инцидент 1 — Chain забит на height 2 (AppHash mismatch)

**Симптом:** Chain stuck на height=2, round 62+; всеки validator предлага различен блок.

**Диагноза:**
```
ERR prevote step: consensus deems this block invalid; prevoting nil
err="wrong Block.Header.AppHash.
  Expected 8A3A96AD57DB94C63F4F4319352CCF4CAB6DCA62AF2B1BCE71A318201F6C4E61,
  got     CDBBCA605777877220E2CFC933156EC4637DD4A4E848E262F71F3E9B08293D87"
```

**Root cause:** `contabo-1` (13.140.139.82) е имал **различен gembad binary** от `contabo-2` и `contabo-3`:

| Host | Binary md5 | AppHash |
|---|---|---|
| 13.140.139.82 | `4b14633fdc69f24cc7b12e79685cd97b` | `8A3A96AD...` ← различен |
| 13.140.139.83 | `52a9fe5932fa53278556a34b6bc4ec06` | `CDBBCA60...` |
| 13.140.139.84 | `52a9fe5932fa53278556a34b6bc4ec06` | `CDBBCA60...` |

Само 2/4 validators (.83 + .84) са съгласни → 2000/4000 = 50% < 2/3 threshold → chain не може да commit.

### Инцидент 2 — node2 (jellyfin, 192.168.100.100) крашва с GLIBC грешка

**Симптом:**
```
/usr/local/bin/gembad: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.38' not found
```

**Root cause:** Новият binary изисква glibc 2.38. Jellyfin е Ubuntu 22.04 (Jammy) с glibc **2.35**. Новият binary е компилиран на по-нова система.

### Инцидент 3 — Conflicting votes след частична поправка

**Симптом:** след смяна само на binary-то на .82 и негов самостоятелен reset:
```
ERR found conflicting vote from ourselves; did you unsafe_reset a validator? height=2 round=7
ERR failed to process message err="conflicting votes from validator 130C621B..."
```

**Root cause:** .83 и .84 са имали закешираните стари гласове на .82 от round 65 в оперативната си памет. Новите гласове на .82 (след reset) са конфликтирали с тях.

---

## Поправки (в реда на изпълнение)

### Fix 1 — Обновяване на binary-то на contabo-1

```bash
# Изтегляне на правилния binary от .83:
ssh root@13.140.139.83 "cat /usr/local/bin/gembad" > /tmp/gembad_new
# md5: 52a9fe5932fa53278556a34b6bc4ec06 ✓

# Качване към .82:
cat /tmp/gembad_new | ssh root@13.140.139.82 \
  "cat > /usr/local/bin/gembad.new && chmod +x /usr/local/bin/gembad.new && mv /usr/local/bin/gembad.new /usr/local/bin/gembad"
```

### Fix 2 — Едновременен unsafe-reset-all на всичките 3 Contabo validator-а

Необходим за изчистване на старите гласове от паметта на всички nodes.

```bash
# Спиране на всичките 3 едновременно
for ip in 13.140.139.82 13.140.139.83 13.140.139.84; do
  ssh root@$ip "systemctl stop gembad-val.service" &
done; wait

# Reset на всичките 3 едновременно (--keep-addr-book запазва peers)
for ip in 13.140.139.82 13.140.139.83 13.140.139.84; do
  ssh root@$ip "gembad comet unsafe-reset-all --home /root/.gembad --keep-addr-book" &
done; wait

# Старт на всичките 3 едновременно
for ip in 13.140.139.82 13.140.139.83 13.140.139.84; do
  ssh root@$ip "systemctl start gembad-val.service" &
done; wait
```

**Резултат:** chain commit на height 2, 3, 4... ✅

### Fix 3 — Archive node на .82

Archive node (`gembad-archive.service`, home `/root/.gembad-archive`) е имал стари данни от предишната верига.

```bash
ssh root@13.140.139.82 "
systemctl stop gembad-archive.service
gembad comet unsafe-reset-all --home /root/.gembad-archive --keep-addr-book
cp /root/.gembad/config/genesis.json /root/.gembad-archive/config/genesis.json
systemctl start gembad-archive.service
"
```

**Допълнително:** `unsafe-reset-all` е reset-нал `node_key.json` на contabo-1 → новият node_id на .82 е `44935754a7ea7e5ced5528eb39b5b4f6de73d3bb`. Peers config-ът на archive node е обновен с Python:

```bash
ssh root@13.140.139.82 "python3 -c \"
import re
cfg = open('/root/.gembad-archive/config/config.toml').read()
new_peers = '44935754a7ea7e5ced5528eb39b5b4f6de73d3bb@127.0.0.1:26656,5473057935d09332c6051e7e83902ae226e060d2@13.140.139.83:26656,b7588b7dcd3e90bc0306dce68f7c95c5306d74a6@13.140.139.84:26656'
cfg = re.sub(r'^(persistent_peers) = .*', r'\1 = \\\\\"' + new_peers + '\\\\\"', cfg, flags=re.MULTILINE)
cfg = re.sub(r'(experimental_max_gossip_connections_to_(?:persistent|non_persistent)_peers) = .*', r'\1 = 0', cfg)
open('/root/.gembad-archive/config/config.toml', 'w').write(cfg)
\""
```

> **⚠️ Бъг открит:** regex-ът `persistent_peers = .*` е засегнал и полетата `experimental_max_gossip_connections_to_persistent_peers` и `_to_non_persistent_peers` (защото съдържат `persistent_peers` в имената), заменяйки integer 0 с node_id string. Резултат: archive node crашва с "cannot parse value as int". Поправено с допълнителен `re.sub` за тези две полета. **За в бъдеще: използвай `^persistent_peers = .*` (с `^` и `re.MULTILINE`) за точно matching.**

### Fix 4 — node2 (jellyfin) — Docker workaround за glibc несъвместимост

> **Важна бележка:** node2 е работел на стария binary (glibc ≤ 2.35 compatible). Новият binary изисква glibc 2.38 и **не може да стартира нативно** на Ubuntu 22.04 (glibc 2.35). Операторът е инсталирал новия binary на node2 по време на re-genesis процедурата. **TODO: компилирай gembad за Ubuntu 22.04 (target glibc 2.35) и смени Docker с native binary.**

```bash
# 1. Стартиране на Docker daemon (не е работел)
sudo systemctl start docker && sudo systemctl enable docker

# 2. Изтегляне на Ubuntu 24.04 image (има glibc 2.38)
sudo docker pull ubuntu:24.04

# 3. Reset на node2 data (binary не може да стартира нативно, затова via Docker)
sudo docker run --rm \
  -v /home/slavy/.gembad-testnet-node2:/data \
  -v /usr/local/bin/gembad:/usr/local/bin/gembad:ro \
  ubuntu:24.04 \
  /usr/local/bin/gembad comet unsafe-reset-all --home /data --keep-addr-book

# 4. Обновяване на persistent_peers с новите node_ids
python3 -c "
import re
cfg = open('/home/slavy/.gembad-testnet-node2/config/config.toml').read()
new_peers = '44935754a7ea7e5ced5528eb39b5b4f6de73d3bb@13.140.139.82:26656,5473057935d09332c6051e7e83902ae226e060d2@13.140.139.83:26656,b7588b7dcd3e90bc0306dce68f7c95c5306d74a6@13.140.139.84:26656'
cfg = re.sub(r'^(persistent_peers) = .*', r'\1 = \"' + new_peers + '\"', cfg, flags=re.MULTILINE)
cfg = re.sub(r'(experimental_max_gossip_connections_to_(?:persistent|non_persistent)_peers) = .*', r'\1 = 0', cfg)
open('/home/slavy/.gembad-testnet-node2/config/config.toml', 'w').write(cfg)
"

# 5. Нов systemd service (Docker-based)
sudo tee /etc/systemd/system/gembad.service > /dev/null << 'EOF'
[Unit]
Description=GembaBlockchain testnet validator node2 (Docker/Ubuntu24)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStartPre=-/usr/bin/docker rm -f gembad-node2
ExecStart=/usr/bin/docker run --rm --name gembad-node2 \
  --network host \
  -v /home/slavy/.gembad-testnet-node2:/home/slavy/.gembad-testnet-node2 \
  -v /usr/local/bin/gembad:/usr/local/bin/gembad:ro \
  ubuntu:24.04 \
  /usr/local/bin/gembad start \
    --home /home/slavy/.gembad-testnet-node2 \
    --chain-id gemba-testnet-1 \
    --evm.evm-chain-id 821207 \
    --minimum-gas-prices 1000000000agmb \
    --json-rpc.enable=true \
    --json-rpc.address 0.0.0.0:8545 \
    --json-rpc.ws-address 0.0.0.0:8546 \
    --json-rpc.api eth,net,web3,txpool,debug
ExecStop=/usr/bin/docker stop gembad-node2
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl start gembad.service
```

---

## Node_ids след re-genesis (ОБНОВЕНИ)

`unsafe-reset-all` е reset-нал `node_key.json` на contabo-1 — **node_id-ът му се е сменил.**

| Moniker | Host | Нов node_id | Стар node_id |
|---|---|---|---|
| gemba-tn-contabo-1 | 13.140.139.82 | `44935754a7ea7e5ced5528eb39b5b4f6de73d3bb` | `d9ffd12b33cc3ffd6b82ffecbd8580e6e1c151fc` |
| gemba-tn-contabo-2 | 13.140.139.83 | `5473057935d09332c6051e7e83902ae226e060d2` | `25948c96c08225bfcc0d4dfbb4112c8fea5d0b01` |
| gemba-tn-contabo-3 | 13.140.139.84 | `b7588b7dcd3e90bc0306dce68f7c95c5306d74a6` | `94a56937be9fc48d63f8ede76d9c62cd46d89647` |
| gemba-tn-val-node2 | 192.168.100.100 | `63b04f9bf6de156c20b90eede735ccf759f29029` | `62c69ca1cfa5ebd5f63e53acd7f3aa767b12b055` |

> Стандартна препоръка: `unsafe-reset-all --keep-addr-book` **не трябва** да reset-ва `node_key.json`. Провери коя версия на gembad/CometBFT прави това и дали е бъг или промяна в поведението.

---

## Текущо състояние (2026-06-06 ~13:15 CEST)

| Компонент | Статус |
|---|---|
| Chain | ✅ Жива, ~2-5 s/блок, 4/4 validators, height 650+ |
| contabo-1 (.82) | ✅ Валидира, binary `52a9fe...` |
| contabo-2 (.83) | ✅ Валидира |
| contabo-3 (.84) | ✅ Валидира |
| node2 (jellyfin, val-3) | ✅ Валидира (**via Docker**, Ubuntu 24.04); unjailed (txhash `E7577C9E...`) |
| Archive node (.82) | ✅ Синхронизира, height 650+ |
| Public RPC | ✅ `https://testnet.gembascan.io/rpc` |
| Gas limit | ✅ **100M** (`0x5f5e100`) — потвърдено от genesis |
| Governance | ✅ Деплойнато — GembaTimelock, GembaVotes, GembaGovernor, EmergencyPause |
| Reserve contracts | ✅ Деплойнати и ФИНАНСИРАНИ — Faucet 30M, Foundation 15M, DAO 10M, Contingency 10M |
| DEX contracts | ✅ Деплойнати — WGMB, GembaSwapFactory, Router02, GembaNativePoolFactory, LiquidityLocker |
| GembaScan (Blockscout) | ✅ Индексира от блок 1, FIRST_BLOCK=1 fix, height 650+ видимо публично |
| Contract verification | ⚠️ DEX core/router ✅; governance/reserves — bytecode mismatch, TODO retry |

---

## Стъпки 4–9 — изпълнение (2026-06-06 сесия 2)

### Стъпка 4: Re-deploy contracts ✅

**Намиране на ключовете:** genesis-ът е генериран с `BASE=/tmp/gemba-regenesis` (не с `~/.gemba-testnet`). Всички reserve EOA ключове са намерени в `/tmp/gemba-regenesis/node0/keyring-test/`.

**Деплой на Governance + Reserves:**
```bash
cd contracts
forge script script/DeployGovernance.s.sol:DeployGovernance \
  --rpc-url https://testnet.gembascan.io/rpc \
  --chain-id 821207 \
  --private-key $FOUNDER_PK \
  --broadcast --slow
```

**Деплой на DEX:**
```bash
DEPLOYER_PK=$FOUNDER_PK \
forge script script/DeployDex.s.sol:DeployDex \
  --rpc-url https://testnet.gembascan.io/rpc \
  --chain-id 821207 \
  --private-key $FOUNDER_PK \
  --broadcast --slow
```

### Стъпка 5: Fund reserves ✅

Резервите са финансирани ДИРЕКТНО от DeployGovernance.s.sol скрипта (функцията `_fund()`):
- Founder праща 0.1 GMB gas buffer към всеки reserve EOA
- Reserve EOA-тата изпращат пълния баланс към контрактите

Потвърдени баланси:
- Faucet: **30,000,000 GMB** ✓
- FoundationTreasury: **15,000,000 GMB** ✓
- DAOReserve: **10,000,000 GMB** ✓
- ContingencyReserve: **10,000,000 GMB** ✓

### Стъпка 6: Wire governance ⚠️ (частично)

Governance е деплойнато и правилно конфигурирано:
- GembaTimelock: Governor може да предлага; deployer renounced admin
- GembaGovernor: 1 GMB = 1 vGMB, quorum 50%, supermajority 66%, 5-min timelock
- EmergencyPause: 2-of-3 guardians (founder + tnfaucet + val0 EVM адреси)

**TODO:** пълен end-to-end тест на proposal flow (propose → vote → queue → execute).

### Стъпка 7: Verify contracts ⚠️

`./script/verify-all.sh` изпълнено:
- GembaSwapFactory ✅, GembaSwapRouter02 ✅
- Governance + Reserves: "local bytecode doesn't match on-chain bytecode" — ще се retry с explicit constructor args

### Стъпка 8: Re-point explorer ✅

Blockscout e рестартиран с `docker compose down -v && docker compose up -d` (нова DB, re-index от блок 1).
Fix: добавен `FIRST_BLOCK=1` в `envs/backend.env` — изчистен loop в `block_catchup` fetcher за несъществуващ EVM block 0. Explorer индексира коректно.

### Стъпка 9: Contract addresses ✅

Вижте `docs/testnet-deployments.md` — актуализиран с всички нови CA адреси.

---

## Fix: val-3 unjail (2026-06-06 сесия 2)

**Проблем:** val-3 (node2) е jailed след ~600 блока downtime (10 slashing, 990 GMB оставащи от 1000).

**Root cause:** node2 е работел като peer (не validator) докато бинарният е бил несъвместим. След Docker fix-а, consensus ключът е бил правилен (съответства на genesis gentx), но validator-ът е бил вече jailed.

**Fix:**
```bash
# Ключът е в /tmp/gemba-regenesis/node3/keyring-test/
# Копиран на contabo-1 за unjail от local RPC (port 26657 blockat от ufw за external):
scp /tmp/gemba-regenesis/node3/keyring-test/val3.info root@13.140.139.82:/tmp/val3-home/keyring-test/
scp /tmp/gemba-regenesis/node3/keyring-test/7b75ca2344*.address root@13.140.139.82:/tmp/val3-home/keyring-test/

ssh root@13.140.139.82 "gembad tx slashing unjail --from val3 --keyring-backend test \
  --home /tmp/val3-home --chain-id gemba-testnet-1 --node http://localhost:26657 \
  --gas 200000 --gas-prices 1000000000agmb --yes"
# txhash: E7577C9EE6D684C1B9A3A8EBED2B6CB37D1BD5AF013BC048E2632CCCBC8EBFD5
```

**Резултат:** 4/4 validators BONDED, active.

---

## Fix: Blockscout FIRST_BLOCK=1 (2026-06-06 сесия 2)

**Проблем:** `block_catchup` fetcher в безкраен loop — `last_block_number: 0, missing_block_count: 1`. Cosmos EVM блок 0 (EVM genesis) има СЪЩИЯ hash като блок 1 → Blockscout го видя като "gap" и се зацикли.

**Fix:** `echo 'FIRST_BLOCK=1' >> /root/gembascan/envs/backend.env` + `docker compose up -d --force-recreate backend`.

**Резултат:** `"Index already caught up"`, `missing_block_count: 0`.

---

## TODO (нерешени проблеми)

1. **node2 native binary** — компилирай gembad за Ubuntu 22.04 (glibc 2.35) и замени Docker service с нативен.
2. **node_key.json reset** — документирай в halt-recovery runbook (unsafe-reset-all reset-ва node keys).
3. **Contract verification** — retry governance/reserves verification с explicit constructor args.
4. **Governance end-to-end test** — тествай пълен proposal flow на testnet.
5. **Key backup** — `/tmp/gemba-regenesis/` е ephemeral! Копирай `node0/keyring-test/` в сигурно хранилище.
6. **ufw rule** — обмисли отваряне на порт 26657 на 3-те Contabo nodes (за external tx broadcast), или документирай workaround (SSH + local gembad).
