# DevSecOps Web Lab - Roadmap 

> **Terraform + Ansible remain the foundation. Purple Team is the story.**
> English-only · Last updated: 2026-11-05

## 0. Purpose

This lab started as an Infrastructure-as-Code demonstration. It stays one - but the narrative is
now **Purple Team**:

> Deploy the stack **as-is** → attack it from Kali → detect it in Grafana/Loki → document it with
> MITRE ATT&CK and IOCs → harden it with Ansible → **replay the exact same attacks** → compare the
> two runs → investigate the delta.

The portfolio answer is no longer *"I deployed six containers"*. It is:

> *"I built a lab, I attacked it, I detected it, I hardened it, and I can prove the before/after
> with timestamps, logs, and reports."*

**What this roadmap is not:** a SIEM, a production platform, a CI/CD project, or a red-team tooling
course. Those are mentioned as next steps, not implemented.

---

## 1. Principles

1. **Two runs, one script.** Red and Blue use the same frozen attack script (`attack-v1`). Never
   rewrite it between runs.
2. **Everything is timestamped in UTC ISO 8601** (`2026-11-05T14:00:00Z`), with a `run-id`, the Git
   commit, and the script SHA-256.
3. **Evidence over claims.** Every statement in a report links to a log line, a JSONL result, or a
   screenshot.
4. **The README is written last** (Phase 7), when the results are known.
5. **MySQL is an independent target**, not Juice Shop's database. Both write logs to the same
   volume; that is the only relationship.
6. **Detection before prevention.** The Red run uses the WAF in `DetectionOnly`; the Blue run turns
   it to `On`. This is the whole point of the comparison.
7. **Simple beats impressive.** One dashboard, two alerts, one channel, two reports.

### What changed from the old V3

| Old V3 | This roadmap |
|---|---|
| SOC-only, 7 phases, 4 alert rules, Discord **and** Telegram | Purple-first, 8 phases, 2 alerts, one channel |
| Attacker container + Kali guide | Kali VM + bash/python/curl, no extra container |
| 3 incident reports | 2 reports (Red + Blue) |
| CI + Trivy as a phase | Mentioned as a production next step |
| Referenced deleted files (`V2_ROADMAP.md`, `.github/`, `attacker/`, `detect/`) | Only current files |
| No before/after methodology | Frozen script + two runs + comparison table |

---

## 2. Phase 0 - Make the stack actually deployable (blockers)

> **Do this first. Nothing else is credible if `make deploy` fails.**

### 2.1 Image tags that do not exist

Verified against Docker Hub on 2026-11-05. Three pinned tags are wrong, so `terraform apply` fails
at pull time:

| Resource | Current (broken) | Correct tag | Status |
|---|---|---|---|
| Juice Shop | `bkimminich/juice-shop:20.3.0` | `bkimminich/juice-shop:v20.3.0` | 404 → 200 |
| Alloy | `grafana/alloy:1.21.2` | `grafana/alloy:v1.21.2` | 404 → 200 |
| OWASP CRS | `owasp/modsecurity-crs:4.30.0-nginx` | `owasp/modsecurity-crs:4.30.0-nginx-202610180210` | 404 → 200 |
| Grafana | `grafana/grafana:13.3.0` | unchanged | 200 |
| Loki | `grafana/loki:3.7.8` | unchanged | 200 |
| MySQL | `mysql:8.4` | unchanged | 200 |

- [ ] Fix the three tags in `terraform/main.tf`.
- [ ] Run `terraform init` and commit `.terraform.lock.hcl` (currently ignored).
- [ ] Relax `required_version = "1.17.1"` to `>= 1.5`.
- [ ] Remove the `depends_on` on `docker_image` resources (images do not depend on containers).

**DoD:** `terraform apply` pulls all six images and starts all six containers.

### 2.2 SELinux blocks every bind mount from the repo (verified)

Environment: Fedora, SELinux **Enforcing**, rootless Podman. The repo is labelled `user_home_t`;
containers run as `container_t` and are denied.

Reproduction (verified on this machine):

```bash
podman run --rm -v "$PWD/terraform/grafana_provisioning:/x:ro" busybox ls /x
# ls: can't open '/x': Permission denied

podman run --rm --security-opt label=disable \
  -v "$PWD/terraform/grafana_provisioning:/x:ro" busybox ls /x
# dashboards  datasources
```

Affected mounts:

| Container | Host path | Symptom |
|---|---|---|
| Grafana | `terraform/grafana_provisioning/{datasources,dashboards}` | no datasource, no dashboard |
| Alloy | `ansible/files/alloy/config.alloy` | Alloy cannot start / no pipeline |
| MySQL | `terraform/init.sql` | database not initialised |

`chmod -R a+rX` fixes UID 472 traversal but **does not fix SELinux**. It is necessary, not
sufficient.

- [ ] Add `security_opts = ["label=disable"]` to `grafana`, `alloy`, and `mysql` in
      `terraform/main.tf`.
  - Provider v3 supports `security_opts`.
  - Provider v4 adds `selinux_relabel = "z"` on the `volumes` block, which is cleaner if you
    upgrade.
- [ ] Keep the `chmod -R a+rX terraform/grafana_provisioning` step in the Makefile.
- [ ] Document `make deploy` as the only supported entry point: a raw `terraform apply` skips the
      `chmod` and fails on a restrictive umask.
- [ ] Document the trade-off in the README: lab-only; production would bake configs into images or
      use `:z`.

**DoD:** Grafana reads its provisioning folders, Alloy reads its config, MySQL reads `init.sql`.

### 2.3 Grafana provisioning: what actually works (verified)

Reproduction (verified on this machine):

```bash
podman run -d --name gtest --security-opt label=disable -p 3002:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=test \
  -v "$PWD/terraform/grafana_provisioning/datasources:/etc/grafana/provisioning/datasources:ro" \
  -v "$PWD/terraform/grafana_provisioning/dashboards:/etc/grafana/provisioning/dashboards:ro" \
  grafana/grafana:13.3.0

# wait ~90 s for the SQLite migrations, then:
curl -s -u admin:test http://localhost:3002/api/datasources
curl -s -u admin:test http://localhost:3002/api/dashboards/uid/security-overview
podman rm -f gtest
```

Result:

- `loki_datasource.yml` → datasource **Loki** created, `isDefault: true`.
- `dashboard_provider.yml` + `security_overview.json` → dashboard **security-overview** created.
- The provider YAML sitting in the same folder is ignored: Grafana only reads `.json` files
  (verified in `file_reader.go`). No need to move it.
- First boot takes ~90 s (SQLite migrations). The dashboard appears after that.

Remaining hardening:

- [ ] Add `uid: loki` to `loki_datasource.yml` (stable UID; currently auto-generated).
- [ ] Add `"datasource": {"type": "loki", "uid": "loki"}` and `"refId": "A"` to each panel target.
- [ ] Set `"timezone": "utc"` in the dashboard (SOC timestamps).
- [ ] Set `allowUiUpdates: false` and `disableDeletion: true` in `dashboard_provider.yml` once the
      dashboard is stable (GitOps, no drift).
- [ ] Add a Grafana healthcheck or document the ~90 s first-boot wait.
- [ ] Delete the duplicate `grafana/dashboards/security-dashboard.json`; the single source of truth
      is `terraform/grafana_provisioning/dashboards/security_overview.json`.

Note: `meta.provisioned` was `false` in the 13.3.0 API even though `provisionedExternalId` was set.
Cosmetic; the dashboard is served. Do not chase it.

**DoD:** after `make deploy`, `http://localhost:3001` shows the Security Overview dashboard with the
Loki datasource, without any manual click.

### 2.4 Ansible bugs to fix before the first attack

- [ ] **MySQL handler**: `when: ansible_service_mgr == 'systemd'` with `gather_facts: false` →
      undefined variable. Restart the container from the host
      (`community.docker.docker_container` with `state: restarted`) or drop the handler. MySQL in a
      container is PID 1; systemd is not the answer.
- [ ] **`SecDefaultAction` loop**: `lineinfile` with `regexp: '^SecDefaultAction'` replaces the same
      (last) line twice. Phase 1 stays `pass`. Use two distinct regexps
      (`^SecDefaultAction "phase:1` and `^SecDefaultAction "phase:2`).
- [ ] **`curl` path traversal**: add `--path-as-is`, otherwise curl normalises `../` and the test
      proves nothing.
- [ ] **`no_log: true`** on every task that manipulates `mysql_root_password`, `app_password`, or
      vault variables.
- [ ] **DB naming**: `MYSQL_DATABASE=juiceshop` and `app_database: juiceshop` imply a link that does
      not exist. Rename to a neutral lab database (e.g. `bank_lab`) or rely on `init.sql`.
- [ ] **`gather_facts: false` + `ansible_service_mgr`** is a general trap; check every handler.

**DoD:** `ansible-playbook --syntax-check` passes, and a full `site.yml` run ends green.

### 2.5 Repo hygiene

- [ ] Fill `docs/reports/template.md` (it is empty).
- [ ] Rebuild `docs/evidences/` during Phase 2/6 (it is empty; every README image is currently
      broken).
- [ ] Do **not** patch `README.md` now; it is rewritten in Phase 7.
- [ ] Keep `docs/ISSUES.md` as the RCA log; add the new findings above to it.

**Phase 0 DoD:** `make deploy` works from a clean clone; Grafana shows the dashboard;
`make configure` is green; the three blockers are documented.

---

## 3. Conventions

```text
runs/
  red-20261105T140000Z/
    meta.json          # git commit, image tags, script sha256, profile, start/end UTC
    results.jsonl      # one line per attack
    raw/               # curl/sqlmap/nmap raw output
    screens/           # timestamped screenshots
  blue-20261107T090000Z/
    ...
docs/evidences/<run-id>/   # published evidence
```

- `run-id`: `red-<UTC>` / `blue-<UTC>`.
- User-Agent marker: `Lab-Run/<run-id>` → direct LogQL filter.
- Git tags: `baseline-v1`, `attack-v1`, `hardened-v1`.
- Report names: `docs/reports/red-2026-11-05.md`, `docs/reports/blue-2026-11-07.md`.
- Timestamps: `2026-11-05T14:00:00Z`, never local time.
- Evidence: no fabricated timestamps, no uncropped secrets.

---

## 4. The Purple Loop

### Phase 1 - Baseline "as-is" + observability (1 day)

**Goal:** deploy the vulnerable state, but make the traffic visible.

- [ ] Split Ansible into two explicit profiles:
  - `baseline.yml`: `setup-python` + Nginx JSON logs + symlink replacement. No ModSecurity change,
    no DB hardening.
  - `hardening.yml`: `waf-setup.yml` (blocking) + `db-hardening.yml`.
  - `site.yml`: `baseline` + `hardening` + `monitoring.yml` (full).
  - Extract the log tasks into `waf-logs.yml` and import it from `baseline.yml` and
    `waf-setup.yml` to avoid duplication.
- [ ] Keep the WAF in `DetectionOnly` in Terraform for the baseline
      (`MODSEC_RULE_ENGINE=DetectionOnly`). The hardening playbook flips it to `On`.
- [ ] `make baseline` → 6 containers, WAF reachable on `:8080`, Grafana on `:3001`.
- [ ] Generate traffic (`curl http://localhost:8080/...`) and verify it appears in Grafana.
- [ ] Capture `runs/red-<id>/meta.json` and tag `baseline-v1`.

**DoD:** traffic passes, logs are visible in Loki/Grafana, the baseline is reproducible and tagged.

### Phase 2 - Red run: timestamped attacks from Kali (1.5 days)

**Goal:** produce raw, timestamped evidence from the attacker side.

- [ ] Web axis: recon, SQLi, XSS, LFI (`--path-as-is`), command injection, login brute force.
- [ ] DB axis (independent target): direct `3306`, anonymous account, `root@%`, TLS requirement,
      `local-infile`.
- [ ] `scripts/attacks/killchain.sh`: `set -euo pipefail`, `TARGET=`, `RUN_ID=`, `OUT_DIR=`, JSONL
      output.
- [ ] Every request carries `User-Agent: Lab-Run/<run-id>`.
- [ ] Save raw outputs + screenshots under `runs/<run-id>/`.
- [ ] **Freeze**: commit, tag `attack-v1`, record the SHA-256 in `meta.json`.

**DoD:** every attack has a UTC timestamp, a status code, and a raw artifact; the script is frozen.

### Phase 3 - Detection & SOC visibility (1 day)

**Goal:** prove every Red attack is findable in Grafana.

- [ ] LogQL queries per attack (payload in `uri`, `403`, `401`, volume).
- [ ] One dashboard, 4 panels max: volume, 4xx/403, top URIs, top IP/User-Agent.
- [ ] **2 alerts max**, one channel (Discord webhook):
  - `waf-403-spike`: `sum(count_over_time({job="waf"} |= "403" [1m])) > 10` for 1m.
  - `auth-bruteforce`: `sum(count_over_time({job="waf"} |= "401" [1m])) > 10` for 1m.
- [ ] Optional third: `scan-spike` (volume > 60/min) - only if it stays simple.
- [ ] Provision the alerting files under `terraform/grafana_provisioning/alerting/`
      (`contact_points.yml`, `alert_rules.yml`, `notification_policies.yml`) and mount the folder in
      `terraform/main.tf`.
- [ ] Keep the Discord webhook in `terraform.tfvars` / an environment variable, never in Git.
- [ ] Verify the Red timeline at an absolute UTC range.

**DoD:** the Red run can be reconstructed in Grafana in under 5 minutes.

### Phase 4 - Red report (1 day)

**Goal:** the SOC deliverable for the attack side.

- [ ] `docs/reports/red-<date>.md`: executive summary, scope, methodology, UTC timeline.
- [ ] OWASP Top 10 2025 + MITRE ATT&CK mapping (6–8 techniques max).
- [ ] IOC table: source IP, User-Agent, payloads, timestamps, HTTP codes.
- [ ] References to `runs/<run-id>/...`.
- [ ] Findings: what passes, what is visible, what is not blocked.

**DoD:** one line = attack → timestamp → log line → technique → result.

### Phase 5 - Blue hardening with Ansible (1 day)

**Goal:** harden through code, not manual clicks.

- [ ] `make harden` → `hardening.yml` (WAF `On`, `deny:403`, exclusions, DB hardening).
- [ ] WAF: `SecRuleEngine On`, both `SecDefaultAction` phases, targeted exclusions.
- [ ] DB: anonymous users, `root@%`, `validate_password`, TLS, `local-infile=0`, least privilege.
- [ ] Keep MySQL reachable on `3306` for the Blue run so the same attack can be replayed; the delta
      is auth/TLS, not reachability. Restrict the port after the comparison if desired.
- [ ] Hygiene: `no_log`, secrets, documented `bind-address`.
- [ ] Tag `hardened-v1` + `runs/blue-<id>/meta.json` (same fields as Red).

**DoD:** WAF blocks, DB is hardened, legitimate traffic is not regressed, everything is versioned.

### Phase 6 - Blue run + comparative investigation (1.5 days)

**Goal:** the final proof.

- [ ] Replay **the same `attack-v1`**, same payloads, new `run-id`.
- [ ] Comparison table:

| Attack | Red timestamp | Red status | Detected? | Blue timestamp | Blue status | Blocked? | Delta |
|---|---|---|---|---|---|---|---|

- [ ] `docs/reports/blue-<date>.md`: investigation, before/after, RCA, remediation validation,
      lessons.
- [ ] Grafana screenshots at both absolute time ranges.

**DoD:** the comparison is readable and the attack script was not modified.

### Phase 7 - Final README & packaging (1 day)

**Goal:** write the showcase only now.

- [ ] `README.md`: real architecture, 4-command quickstart (`make baseline`,
      `make attack RUN_ID=red-...`, `make harden`, `make attack RUN_ID=blue-...`), Red vs Blue
      results, screenshots, skills.
- [ ] `docs/README.md` + `docs/reports/README.md` complete.
- [ ] Evidence index; no broken links.
- [ ] Optional: demo GIF.
- [ ] Every README claim is backed by a file.

**DoD:** a recruiter follows Red → Blue → report in under 10 minutes.

---

## 5. Attack matrix

| Axis | Attack | Tool | OWASP 2025 | MITRE | Red expected | Blue expected |
|---|---|---|---|---|---|---|
| Web | Recon | curl/ffuf | A02 | T1595.002 | 200 / paths visible | 403 / filtered |
| Web | SQL injection | curl/sqlmap | A05 | T1190 | 200 (passes) | 403 |
| Web | XSS | curl | A05 | T1189 | 200 (passes) | 403 |
| Web | LFI / path traversal | curl `--path-as-is` | A01 | T1083 | 200 (passes) | 403 |
| Web | Command injection | curl | A05 | T1059 | 200 (passes) | 403 |
| Web | Login brute force | python/curl | A07 | T1110.001 | repeated 401 | 401 + alert |
| Network | Port scan | nmap | - | T1046 | visible | visible + alert |
| DB | Auth / anonymous / TLS | mysql client | A07/A02 | T1110 | connection possible | refused |

---

## 6. What the portfolio demonstrates

1. **Infrastructure as Code** - Terraform + Ansible, reproducible from a clean clone.
2. **WAF engineering** - ModSecurity + CRS, blocking mode, false-positive tuning.
3. **Detection engineering** - LogQL queries, two alert rules, thresholds.
4. **Alert routing** - one webhook, simple and reliable.
5. **Investigation** - dashboard pivots, IOC extraction, ATT&CK mapping.
6. **Incident response** - two structured reports, RCA, corrective actions.
7. **Purple Team** - same attack, two states, measurable delta.
8. **Engineering hygiene** - pinned images, frozen scripts, UTC timestamps, evidence.

---

## 7. Explicitly out of scope

Mention these in the README as "production next steps", do not implement them:

- CI/CD (GitHub Actions, `terraform fmt`, `ansible-lint`, `shellcheck`, Trivy).
- Dedicated attacker container (Kali VM + bash/python/curl is enough).
- Telegram **and** Discord (one channel only).
- Three or four alert rules (two is enough).
- Three or more incident reports (two is enough).
- Advanced investigation dashboard (four panels is enough).
- SIEM (Wazuh/Splunk), Sigma rules, SOAR.
- Automated remediation (response is manual, on purpose).
- Rewriting the kill chain between Red and Blue (**forbidden**).

---

## 8. Definition of Done (global)

- [ ] `make deploy` works from a clean clone.
- [ ] Grafana provisions the datasource and dashboard without manual clicks.
- [ ] Two runs, same script, same payloads, UTC timestamps.
- [ ] One Red/Blue comparison table.
- [ ] Two reports (Red + Blue) with MITRE + IOC.
- [ ] One dashboard + two alerts.
- [ ] One final README, accurate.
- [ ] No secrets, no uncropped evidence.
- [ ] `terraform fmt -check` and `ansible-playbook --syntax-check` pass locally.

---

## 9. Timeline

| Phase | Duration |
|---|---|
| 0 - Deployability blockers | 1 day |
| 1 - Baseline | 1 day |
| 2 - Red run | 1.5 days |
| 3 - Detection | 1 day |
| 4 - Red report | 1 day |
| 5 - Blue hardening | 1 day |
| 6 - Blue run + report | 1.5 days |
| 7 - README & packaging | 1 day |
| **Total** | **~9 days** |

---

## 10. Honest limits

- Not a real SIEM (Splunk/QRadar); same workflow, miniature scale.
- Single host, single subnet, no DMZ, no production data.
- Juice Shop is deliberately vulnerable; the incident is simulated by design.
- No automated remediation; response is manual, on purpose.
- Grafana/Loki have no TLS or SSO in this lab.
- MySQL is exposed on `3306` for the Red run; the Blue run documents the restriction.
- `general_log = 1` is useful for DB attack detection but logs sensitive data; production would use
  the audit plugin and scrub secrets.
