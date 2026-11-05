# DevSecOps Web Lab - Roadmap V3

> **Supersedes `V2_ROADMAP.md`** (kept as a historical record).
> English-only · Ordered by **SOC portfolio value**, not by infrastructure convenience.
> Last updated: 2026-10-19

## Objective

Turn the lab into a **complete, demonstrable SOC workflow**: detect → alert → investigate →
document → improve - on top of the DevSecOps foundation (IaC, WAF, hardening) that is already solid.

Final result: a portfolio where you can say *"I detected it, I investigated it, I documented the
IOC, I proposed the fix"* - and show the files that prove it.

---


## V3 Phases (SOC-priority order)

### Phase 0 - Documentation consistency · *~1 hour · trust gate*

Nothing else matters if the README lies.

- [ ] `README.md`: Promtail → **Alloy**, 5 → **6 containers**, `attack_simulation/` → `scripts/attacks/`,
      `tests.sh` → `scripts/installs.sh`, fix broken image path `docs/evidences/bunch/bunch/...`
- [ ] `docs/incident-report.md`: conclusion says Promtail → Alloy
- [ ] `docs/Resources.md`: current-stack mentions → Alloy (historical Promtail refs annotated)
- [ ] `docs/README.md`: fill the empty docs index

**DoD:** every claim in the docs matches `terraform/main.tf` and `docs/architecture.md`.

---

### Phase 1 - Detection content: MITRE ATT&CK + IOC · *own deliverable*

The mapping must be **yours**, not copied from MITRE's site.

- [ ] `scripts/attacks/{attack_name}.sh`: print ATT&CK technique per phase + summary table
- [ ] `docs/incident-report.md`:
  - Technique column added to the kill-chain timeline table
  - New **Indicators of Compromise** section: source IP, `curl/` User-Agent, SQLi/XSS/LFI
    payload strings, timestamps, returned status codes
  - Mark recommendation *"Grafana alert on 403 spike"* as ✅ implemented (after Phase 2)

**DoD:** a recruiter can open one file and see technique ↔ log line ↔ IOC ↔ remediation.

---

### Phase 2 - Alerting: Discord + Telegram · *SOC core*

All via **Grafana file provisioning in Terraform** (no manual UI work). Schema verified against
official Grafana provisioning docs (2026-10).

New files under `terraform/grafana_provisioning/alerting/` - **3 separate files** so one bad
contact point can't break rule provisioning:

**`alert_rules.yml`** - folder `SOC`, group `waf-detections`, interval 1m:

| Rule UID | Query (LogQL) | Threshold | For | Severity |
|---|---|---|---|---|
| `waf-403-spike` | `sum(count_over_time({job="waf"} \|= "403" [1m]))` | > 10 | 1m | high |
| `waf-block-ratio` | `(sum(count_over_time({job="waf"} \|= "403" [5m])) / sum(count_over_time({job="waf"} [5m]))) * 100` | > 50 | 1m | critical |
| `auth-bruteforce` | `sum(count_over_time({job="waf"} \|= "401" [1m]))` | > 10 | 1m | high |
| `traffic-scan-spike` | `sum(count_over_time({job="waf"} [1m]))` | > 60 | 1m | medium |

- All aggregated → single series (multi-series-safe), `noDataState: OK`, `execErrState: Alerting`
- No secrets in `data.model` (the only field env interpolation doesn't touch)

**`contact_points_discord.yml` / `contact_points_telegram.yml`** (split for failure isolation):

```yaml
settings:
  url: $SOC_DISCORD_WEBHOOK_URL          # env interpolation - supported
  # telegram: bottoken: $SOC_TELEGRAM_BOT_TOKEN / chatid: $SOC_TELEGRAM_CHAT_ID
```

**`notification_policies.yml`** - routing that degrades gracefully:

- Root → `soc-discord` (fallback, gets everything)
- First child route → `soc-telegram`, `continue: true`, matcher `['severity','=~','critical|high']`
- Second sibling → `soc-discord` (match-all): **Discord is always notified even if the
  Telegram token is empty**

**Supporting changes:**
- [ ] `loki_datasource.yml`: add explicit `uid: loki` (stable UID for rule references)
- [ ] `terraform/variables.tf`: 3 sensitive vars (default `""`) + `enable_attacker` (default `false`)
- [ ] New `terraform/example.tfvars` (already whitelisted in `.gitignore`)
- [ ] `terraform/main.tf`: mount `alerting/` → `/etc/grafana/provisioning/alerting`, pass env vars
- [ ] `Makefile`: `alert-test` (curls the Discord webhook read from tfvars → instant verification),
      `validate` (fmt -check, terraform validate, ansible syntax-check, shellcheck -S error)

**DoD:** `make deploy && make alert-test` → test message in Discord; launching an attack produces
an alert in Discord/Telegram within ~1–2 minutes.

---

### Phase 3 - Investigation workflow · *dashboard + attack script*

**New `terraform/grafana_provisioning/dashboards/investigation.json`:**
- [ ] Raw WAF log stream panel with `$job` / status filters
- [ ] Top 10 blocked IPs: `topk(10, sum by (remote_addr) (count_over_time({job="waf"} |= "403" [$__range])))`
- [ ] Suspicious User-Agents: `topk(10, count by (http_user_agent) (count_over_time({job="waf"} [$__range])))`
- [ ] Timeline for a specific source IP (`$ip` variable) - pivot from alert → dashboard

**`scripts/attacks/` extensions:**
- [ ] Per-phase MITRE output (from Phase 1)
- [ ] **Phase 6 - Brute force:** 12× bad `POST /rest/user/login` → 401s → trips `auth-bruteforce`
- [ ] **Phase 7 - Recon/scan:** `nmap` when available, `/dev/tcp` probes otherwise (graceful fallback)
- [ ] `TARGET=` env override so the script runs inside the attacker container (`http://waf:8080`)

**Investigation methodology** (documented in `docs/`):
`IDENTIFY → CONTAIN → ERADICATE → RECOVER → LESSONS` - applied in the incident reports.

**DoD:** one alert → open dashboard → pivot by IP → timeline reproduced, in under 5 minutes.

---

### Phase 4 - Incident reports ×2 · *the SOC proof*

New `docs/incident-reports/`, mirroring the existing report's structure:

- [ ] `..._bruteforce_login.md` (triage of `auth-bruteforce`)
- [ ] `..._portscan_recon.md` (triage of `traffic-scan-spike`)

Each: executive summary, timeline, ATT&CK mapping, LogQL investigation, IOC table, RCA,
corrective actions, lessons learned - **honestly labeled as controlled simulations**, with
`<!-- EVIDENCE: screenshot -->` placeholders + a capture checklist (you run the simulation,
I don't fabricate timestamps).

**DoD:** 3 incident reports total in the portfolio (SQLi campaign + these two).

---

### Phase 5 - CI + supply chain

**Image pinning** (tags verified on Docker Hub, 2026-10-19):

| Image | Pin | Note |
|---|---|---|
| `grafana/grafana` | `13.2.4` | byte-identical to current `latest` digest |
| `grafana/loki` | `3.6.18` | |
| `grafana/alloy` | `v1.21.0` | |
| `bkimminich/juice-shop` | `v20.3.0` | |
| `mysql` | `8.0.46` | |
| `owasp/modsecurity-crs` | stays `nginx` ⚠️ | changing CRS version blind changes rule behavior - **pin by digest after validating the deployed image** (`podman inspect waf`) - tracked as backlog |

**New `.github/workflows/ci.yml`:**
- [ ] `terraform fmt -check` + `terraform validate`
- [ ] `ansible-playbook --syntax-check` (+ new `ansible/collections/requirements.yml`)
- [ ] `shellcheck -S error`
- [ ] Trivy scan of the images - **informational only** (`continue-on-error`; Juice Shop is
      deliberately vulnerable)

**DoD:** green badge on the repo; a broken playbook or unformatted Terraform fails the PR.

---

### Phase 6 - Attacker infrastructure · *replaces V2's Kali phase*

- [ ] `attacker/Dockerfile`: `debian:bookworm-slim` + `nmap sqlmap curl`
- [ ] Terraform resources gated by `enable_attacker = false` → **zero risk to existing deploys**
- [ ] `Makefile`: `make attack-remote` (script mounted read-only, target `http://waf:8080`)
- [ ] New **`docs/attacker.md`**: Kali VM guide - host-only/bridged networking, target
      `http://<host-ip>:8080`, verify bind address (`ss -tlnp | grep 8080`), SSH port-forward
      fallback if the engine binds to localhost; **no attack tools on the host**

**Attack matrix** (corrected to OWASP **2025**):

| Attack | Tool (attacker only) | OWASP 2025 | MITRE | Expected result |
|---|---|---|---|---|
| SQL Injection | sqlmap (container/Kali) | A05:2025 Injection | T1190 | Blocked (403) |
| Reflected XSS | curl | A05:2025 Injection | T1189 | Blocked (403) |
| Path traversal / LFI | curl | A01:2025 Broken Access Control | T1083 | Blocked (403) |
| Command injection | curl | A05:2025 Injection | T1059 | Blocked (403) |
| Login brute force | script Phase 6 | A07:2025 Auth Failures | T1110.001 | Detected (401 spike) |
| Port scan | nmap / /dev/tcp | N/A | T1046 | Detected (volume spike) |
| Recon burst | curl (script Phase 1) | N/A | T1595.002 | Visible in logs |

**DoD:** full attack run executed **from the attacker container/VM**, alert received, dashboard
pivot works - then evidence captured for Phase 7.

---

### Phase 7 - Packaging & presentation

- [ ] **`detect/README.md`**: the 4 LogQL alert rules - expression, threshold, ATT&CK technique,
      triage steps (reusable detection content recruiters actually read)
- [ ] **`README.md` rewrite**: accurate architecture (Mermaid), 3-command quickstart, alerting
      section, incident-report index, skills demonstrated, technologies
- [ ] **Evidence capture pass**: alert in Discord, investigation dashboard pivots, kill-chain
      screenshots → `docs/evidences/`
- [ ] **Demo**: GIF (or short video) of attack → alert → dashboard → report
- [ ] Commit sequence: one commit per phase (easy to review, shows process)

**Final structure:**

```
DevSecOps-web-lab/
├── terraform/                    # infra + grafana_provisioning (dashboards + alerting)
├── ansible/                      # WAF / DB / Alloy configuration
├── attacker/                     # attacker container image (tools OFF the host)
├── scripts/
│   ├── installs.sh
│   └── attacks/                  # kill chain (7 phases, MITRE-mapped)
├── detect/                       # alert rules as documentation (LogQL + triage)
├── docs/
│   ├── incident-report.md        # SQLi campaign (original)
│   ├── incident-reports/         # brute force + port scan
│   ├── attacker.md               # Kali VM guide
│   ├── ISSUES.md · architecture.md · Resources.md · README.md (index)
│   └── evidences/
├── .github/workflows/ci.yml
├── ROADMAP_V3.md                 # this file
├── V2_ROADMAP.md                 # historical
└── README.md
```

---

## Part 3 - Backlog (explicitly out of scope now)

- Pin `owasp/modsecurity-crs` by digest after validating current deployment
- MySQL query-log threat detection rules (T1059 in SQL logs)
- Grafana → Telegram fully populated (currently provisioned, needs bot token in tfvars)
- Kali VM run-through with evidence (Phase 6 manual step)
- Optional: Grafana OnCall / alert on `waf_errors` job
- Video demo if GIF feels too small

---

## Timeline

| Week | Focus | Deliverables |
|------|-------|--------------|
| **S1** | Phases 0–2 | Docs truthful, ATT&CK/IOC mapped, **alerting live on Discord** |
| **S2** | Phases 3–4 | Investigation dashboard, script v2, 2 incident reports (evidence placeholders) |
| **S3** | Phases 5–6 | CI green, images pinned, attacker container + Kali guide |
| **S4** | Phase 7 | README rewrite, evidence capture, demo GIF |

**~15–25 hours** if evidence capture (Phase 6–7 manual runs) goes smoothly.

---

## What the portfolio demonstrates

1. **Infrastructure as Code** - Terraform + Ansible (already achieved)
2. **WAF engineering** - ModSecurity + CRS, false-positive tuning, blocking mode
3. **Detection engineering** - 4 LogQL alert rules with thresholds & severities (file-provisioned)
4. **Alert routing** - Discord/Telegram webhooks, graceful-degradation policy tree
5. **Investigation** - dashboard pivots, IOC extraction, ATT&CK mapping
6. **Incident response** - 3 structured reports, RCA, corrective actions
7. **Offensive context** - 7-phase attack simulation, tools isolated from the host
8. **Engineering hygiene** - CI, pinned images, shellcheck/ansible-lint

## Honest limits (keep saying this in interviews)

- Not a real SIEM (Splunk/QRadar) - same workflow, miniature scale
- Single subnet, no DMZ, no production data
- Juice Shop is **deliberately vulnerable** - the "incident" is simulated by design
- No automated remediation - response is manual, on purpose (to learn the steps)
