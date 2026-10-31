# Project Analysis — DevSecOps-Web Lab

> **Purpose:** independent assessment of what was built, how well it was managed, what it achieved, and how it maps to a SOC analyst portfolio.
> **Scope of review:** full repository (Terraform, Ansible, attack scripts, dashboards, docs, evidence screenshots, `V2_ROADMAP.md`).
> **Date:** 2026-10-18

---

## 1. Executive Summary

| Dimension | Verdict | Score |
|---|---|---|
| **Technical achievement** | A real, working, fully IaC-defined security lab: 6 containers, hardened WAF + DB, working log pipeline, documented attack/defense cycle | **7.5 / 10** |
| **Project management** | Good scoping, strong troubleshooting discipline, but visible drift between roadmap / README / actual code | **6 / 10** |
| **Documentation & evidence quality** | The strongest part of the project (`ISSUES.md` RCA, incident report, screenshots) | **8.5 / 10** |
| **SOC portfolio fit** | Solid foundation for an **L1/L2 SOC analyst** portfolio, incomplete for a "full SOC workflow" claim | **6.5 / 10** |
| **Overall level** | **Solid junior / early mid-level** — above typical tutorial projects, below production-grade | **7 / 10** |

**One-line verdict:** *A well-engineered defensive lab with excellent troubleshooting documentation, half-way through its own V2 roadmap — it currently demonstrates "deploy + defend + document" convincingly, but not yet "detect + investigate + respond" end-to-end.*

---

## 2. What Was Achieved (by domain)

### 2.1 Infrastructure as Code — ✅ Strong
- **Terraform** provisions 6 containers (WAF, Juice Shop, MySQL, Alloy, Loki, Grafana), an isolated bridge network `devsecops-net`, and a shared named log volume.
- Juice Shop has **no host port** — only reachable through the WAF (`:8080`): real network-level design, not just a compose file.
- Grafana **datasource + dashboard provisioning is code** (`terraform/grafana_provisioning/`), applied through the `Makefile`.
- Sensitive Terraform variables declared `sensitive = true`, `*.tfvars` gitignored.

### 2.2 Configuration Management — ✅ Strong
- **Ansible** master playbook with clean phased order: `setup-python → waf-setup → db-hardening → monitoring`.
- Idempotent tasks (`lineinfile`, `package`, handlers with `notify: Reload Nginx`).
- **Secrets via Ansible Vault** (`vault.yml` correctly gitignored, `vars.yml` references `{{ vault_* }}`).
- Python bootstrap via `raw` module — a genuine Ansible-in-container workaround, correctly documented.

### 2.3 WAF Engineering — ✅ Strongest security artifact
- Nginx + ModSecurity 3 + **OWASP CRS 3.0.15, 846 rules loaded**.
- Moved from `DetectionOnly` → `On` with `SecDefaultAction … deny,status:403` (Issue #12) — a real-world WAF rollout decision, understood and documented.
- **False-positive tuning with narrowly scoped exclusions** (`SecRuleUpdateTargetById 930110 "!ARGS:q"`, socket.io exclusion) — this is *detection engineering*, not just deployment.

### 2.4 Database Hardening — ✅ Good
- CIS-benchmark style MySQL 8.0 controls: anonymous users removed, root restricted to localhost, `validate_password` policy (MEDIUM, 12 chars, complexity), `require_secure_transport = ON`, `local-infile` and symbolic links disabled, least-privilege app user.
- Honest, documented limitation: `audit_log` plugin is Enterprise-only → alternative strategy chosen and explained (Issue #9).

### 2.5 Observability / SOC Tooling — ⚠️ Functional but minimal
- Pipeline **Nginx/MySQL logs → shared volume → Grafana Alloy (read-only) → Loki → Grafana**, JSON access logs, LogQL queries.
- Dashboard "Security Overview" = **3 panels only**: log volume, 403 count, top attacked URIs.
- **No alerting rules, no notification channels, no investigation dashboard** (all planned in V2 Phases 3–4).

### 2.6 Attack Simulation — ⚠️ Working but basic
- `scripts/attacks/simulate_killchain.sh`: 5 phases (recon, SQLi, XSS, path traversal, false-positive check) with OWASP Top 10 2025 mapping and pass/fail verification, plus non-regression checks.
- Pure `curl`-based, single pass, no JSON output, no `--dry-run`, **no MITRE ATT&CK mapping** (promised in roadmap), no SQLMap/Nmap automation in the script.

### 2.7 Documentation & Evidence — ✅ Excellent
- **`docs/ISSUES.md`: 12 incidents with genuine root-cause analysis** (symptom → diagnosis steps → solution → "what to remember" → Docker-vs-Podman comparison). This is the single best portfolio asset in the repo — Issue #12 alone (3 stacked root causes: wrong file path, `DetectionOnly`, `SecDefaultAction pass`) reads like a real war story.
- **`docs/incident-report.md`**: executive summary, timeline table, LogQL analysis, false-positive RCA, remediation, tiered recommendations — close to a professional SOC report format.
- `docs/architecture.md` with mermaid flows, layer responsibilities, end-to-end request narratives, defense-in-depth section.
- `docs/evidences/` — screenshots of blocked attacks, valid pipeline, vault, provisioning (proof of execution, not just claims).

---

## 3. Was It Well Managed? (Project Management Assessment)

### 3.1 What was done well
1. **Written roadmap with phases, effort estimates and a timeline** (`V2_ROADMAP.md`, 3–4 weeks / 40–55h) — the author planned before building.
2. **Honest self-assessment**: the roadmap's "Current State (V1)" table and "Limites du projet" section openly state what doesn't work and what the lab is *not*. That maturity is rare in portfolios.
3. **Problem-driven development**: every roadmap/dev decision is traceable to a real encountered problem, documented in `ISSUES.md` and reproduced in code (e.g. Issue #11 → `chmod -R a+rX` baked into the `Makefile`).
4. **Automation discipline**: a `Makefile` with `install / deploy / configure / attack / status / destroy` gives a reproducible 3-command workflow.
5. **Versioned remediation**: WAF exception rules and hardening live in Ansible, not in a hand-edited container — IaC-closed loop.
6. **Secret hygiene done correctly where it matters** (Vault, gitignore, `sensitive = true`), and the residual weakness (env-var secrets via `podman inspect`) is *itself documented* as Issue #10 with three alternative architectures.

### 3.2 Where management was weak
1. **Roadmap execution stopped around Phase 1.** Status of the 6 V2 phases:

   | V2 Phase | Planned | Actual status |
   |---|---|---|
   | 1 — Fix log pipeline | 2–3 days | ✅ Done (migrated Promtail → Alloy, dashboard live) — *Panel 4 (block ratio) missing* |
   | 2 — Kali attacker + structured script | 3–4 days | ⚠️ Partial (curl script only; no MITRE mapping, no JSON output, no SQLMap/Nmap automation) |
   | 3 — Alerting & thresholds | 2–3 days | ❌ Not started (no Grafana alert rules in repo) |
   | 4 — Investigation workflow & IOCs | 3–4 days | ❌ Not started (no investigation dashboard, no IOC extraction) |
   | 5 — Incident reports (3–4 filled) | 2–3 days | ⚠️ 1 of 3–4 written |
   | 6 — Polish & portfolio | 2 days | ⚠️ Partial — README exists but contains stale content (below) |

2. **Documentation drift (the main quality defect).** The README and some docs describe an *older* state of the project:
   - Log pipeline written as `Promtail` in README, `incident-report.md`, `Resources.md`, while the code and `architecture.md` correctly use **Grafana Alloy**.
   - README says **"5 containers"**, Makefile and `architecture.md` say **6**.
   - README points to `cd attack_simulation && …`, but the folder is `scripts/attacks/`.
   - README project-structure tree lists `tests.sh` and `ansible/files/promtail/` — neither exists (`scripts/installs.sh` and `ansible/files/alloy/` do).
   - Broken image link: `docs/evidences/bunch/bunch/queries-presents.png` (doubled folder).
   - `docs/README.md` is an empty stub with headers only; references an `Incident-report.pdf` that doesn't exist.
   - `V2_ROADMAP.md` has a **corrupted block** (French/English lines duplicated and a stray code fence, lines ~155–158) — leftover of an unfinished edit.
3. **No CI/CD, no lint, no tests** (`terraform validate`/`fmt`, `ansible-lint`, `shellcheck` not wired in) — explicitly acknowledged as future work, but it's the difference between "lab" and "engineered project".
4. **No pinned image versions** — `:latest` on Loki/Grafana/Alloy/Juice Shop (flagged in the incident report's own recommendations, but not fixed).
5. **Mixed language** (FR/EN) across scripts, roadmap and docs — fine for a personal repo, but it weakens presentation for an international SOC audience.

### 3.3 Management verdict
**Well managed *as a learning project*, moderately managed *as an engineering project*.** The discipline that shows is diagnosis, documentation and IaC hygiene; the discipline that's missing is *consistency maintenance* (docs vs code), *scope closure* (finishing V2 phases 3–4–6) and *quality gates* (CI/lint/pinning). The gap between what the README claims and what the repo contains is the #1 thing to fix before publishing this as a portfolio.

---

## 4. Mapping to a SOC Portfolio

### 4.1 SOC function coverage (NIST CSF / typical SOC duties)

| SOC duty | Present? | Evidence in repo | Maturity |
|---|---|---|---|
| **Log collection & centralization** | ✅ | Alloy → Loki pipeline, JSON logs, shared read-only volume | Working, single source only |
| **Threat detection (rules-based)** | ✅ | 846 CRS rules in blocking mode; LogQL `|= "403"` detection | Prevention-heavy, detection-light |
| **Monitoring / dashboards** | ✅ | Security Overview: volume, 403s, top attacked URIs | Minimal (3 panels) |
| **Alerting / triage trigger** | ❌ | None — roadmap Phase 3 not executed | Missing |
| **Attack simulation / purple team** | ⚠️ | 5-phase kill chain, OWASP mapping, evidence screenshots | Basic (curl only) |
| **Incident detection → analysis** | ⚠️ | Incident report §4 LogQL spike analysis | One example |
| **Incident response process** | ⚠️ | Report: timeline, severity, status, remediation, recommendations | Partial — no containment/eradication steps, no IOC block, no ticket |
| **IOC documentation** | ❌ | Roadmap Phase 4.3 never materialized | Missing |
| **False-positive tuning (detection engineering)** | ✅ | CRS 930110 exclusion, socket.io exclusion, verification curl | Real, defensible work |
| **Vulnerability / hardening management** | ✅ | MySQL CIS-style controls, documented Enterprise-vs-Community trade-off | Good |
| **Secrets management** | ✅⚠️ | Ansible Vault + gitignore; env-var weakness documented (Issue #10) | Good awareness, partial implementation |
| **Reporting & communication** | ✅ | Structured incident report with executive summary + recommendations | Strong |
| **Metrics (MTTD / MTTR / KPIs)** | ❌ | None | Missing |
| **Case/ticket workflow (SOAR, playbook)** | ❌ | None | Missing |

### 4.2 Framework mappings actually delivered vs claimed

| Framework | Claimed | Delivered | Comment |
|---|---|---|---|
| **OWASP Top 10 (2025)** | ✅ | ✅ A01, A02, A05 mapped in script + report | Real, verified with HTTP codes |
| **MITRE ATT&CK** | ✅ (roadmap table: T1190, T1189, T1046, T1110…) | ❌ Nowhere in code/docs | Biggest SOC-portfolio gap — one table away from being done |
| **CIS Benchmark (MySQL 8.0)** | ✅ | ✅ Controls applied in `db-hardening.yml` | Good |
| **NIST CSF functions** | implicit | Protect ✅ / Detect ⚠️ / Respond ⚠️ / Identify ⚠️ / Recover ❌ | |
| **NIST 800-61 IR lifecycle** | roadmap Phase 4 | ❌ Not applied (no Identify→Contain→Eradicate→Recover record) | |

### 4.3 What a SOC hiring manager sees

**Strengths (interview-ready stories):**
- *"I built the environment in IaC, attacked it, detected the attack in Loki, and wrote the incident report"* — a complete, credible narrative few junior candidates can tell.
- *"Our WAF was silently passing everything; I traced three stacked root causes (wrong config path, DetectionOnly, SecDefaultAction=pass) and fixed all three in code"* — this is a genuine **L2-level troubleshooting story**.
- *"I tuned a CRS false positive without weakening protection and verified with a non-regression test"* — real detection-engineering reflex.
- Evidence screenshots back every claim.

**Weaknesses a hiring manager will notice:**
- The SOC half of the workflow **stops at dashboards**: no alerts, no triage, no IOC extraction, no containment action, no ticket.
- README/code inconsistencies suggest insufficient review before publishing.
- Single log source (WAF) — no endpoints, network flows, auth logs; correlation is therefore not demonstrated.
- No ATT&CK mapping, no detection rules expressed as reusable content (Sigma/YARA/LogQL alert rules).

### 4.4 Positioning / level it maps to

| Target | Fit |
|---|---|
| **SOC Analyst L1** | ✅ **Strong fit** — monitoring, alert triage basics, report writing all demonstrated |
| **SOC Analyst L2** | ⚠️ Partial — investigation depth and detection engineering show, but no alerting/correlation/IOC workflow yet |
| **DevSecOps / Platform Security (junior)** | ✅ **Strong fit** — arguably the stronger fit: IaC, WAF engineering, hardening, GitOps hygiene |
| **Purple Team / Detection Engineer** | ⚠️ Emerging — false-positive tuning yes, ATT&CK-based detection content no |
| **Security Engineer / mid-level** | ❌ Not yet — no CI security gates, no scale, no automation of response |

**Recommended portfolio positioning:** lead with *"DevSecOps engineer lab with SOC detection & response module"* rather than *"complete SOC workflow"* — the second claim currently overreaches the evidence.

---

## 5. Priority Recommendations (highest ROI first)

1. **Fix documentation drift** (½ day): rename all `Promtail` → `Alloy` in README/incident-report/Resources, correct "5 → 6 containers", fix `attack_simulation/` → `scripts/attacks/`, fix the doubled image path, delete `tests.sh` reference, complete `docs/README.md`, repair the corrupted roadmap block. *This alone raises perceived quality by ~1 point.*
2. **Add MITRE ATT&CK mapping table** to the attack script output + incident report (T1190, T1189, T1083, T1595…). Cheap, high SOC-portfolio value.
3. **V2 Phase 3 — alerting**: 3–4 Grafana alert rules (403 spike > 10/min, 403 ratio > 50%, brute force > 10×401/min) → webhook/Discord. This converts the lab from *dashboard* to *SOC*.
4. **V2 Phase 4 — investigation artifacts**: second dashboard (by IP, by UA, timeline) + an IOC table (IP, UA, payload pattern, timestamps, status codes) inside the incident report.
5. **Write 2 more incident reports** (port scan, brute force) from the roadmap template.
6. **Quality gates**: GitHub Actions running `terraform fmt/validate`, `ansible-lint`, `shellcheck` — even no-deploy CI signals engineering maturity.
7. **Pin image digests/versions** and move DB/Grafana secrets to files or Podman secrets (closes Issue #10).
8. **Add a `detect/` folder with 3 reusable LogQL alert rules or Sigma equivalents** — the missing "detection content" artifact every SOC portfolio should contain.

---

## 6. Final Verdict

- **Was it well managed?** Yes, as a disciplined learning project — strong planning documents, unusually good RCA documentation, correct IaC/secret hygiene, honest self-assessment. It was *partially* managed as an engineering project: V2 phases 3–6 were left open and the documentation drifted from the code.
- **What was achieved?** A reproducible, containerized, IaC-defined web security lab with a genuinely blocking, tuned WAF; a hardened database; a working log pipeline and dashboard; a verified attack/defense cycle; and 12 documented incidents plus 1 structured incident report. That is a **real, demonstrable outcome**, not a tutorial replay.
- **Does it map to a SOC portfolio?** **Yes — for SOC Analyst L1 (and partially L2), with DevSecOps as the stronger secondary axis.** It credibly covers *Monitor / Detect (basic) / Respond (documented)*, but currently lacks the three things that make a SOC portfolio complete: **alerting, IOC/investigation artifacts, and ATT&CK-mapped detection content**. Closing V2 phases 3–5 would move it from "strong foundation" to "complete junior SOC portfolio".

**Overall level: 7/10 — solid junior, credible early-mid potential once the V2 SOC loop (detect → alert → investigate → respond) is closed and the docs are made consistent with the code.**
