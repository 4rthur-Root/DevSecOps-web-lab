# Security Incident Report — DevSecOps Web Lab
**Date :** 2026-06-18  
**Analyst :** KPODONOU K. Gaël  
**Severity :** High (controlled simulation)  
**Status :** Resolved

---

## 1. Executive Summary

A kill chain simulation was conducted on the DevSecOps Web Lab infrastructure to validate the effectiveness of the deployed WAF (Nginx + ModSecurity + OWASP CRS) in front of the OWASP Juice Shop application. The attack covered four phases: reconnaissance, SQL injection, XSS, and path traversal. The WAF detected and blocked all malicious payloads. A false positive was identified and corrected through an exception rule deployed in IaC.

---

## 2. Target Infrastructure

| Component | Role | Technology |
|---|---|---|
| WAF | Reverse proxy + application firewall | Nginx + ModSecurity + OWASP CRS |
| Juice Shop | Vulnerable web app (target) | Node.js / Angular |
| MySQL | Database | MySQL 8.0 (hardened) |
| Loki + Grafana | Log centralization and visualization | Grafana Stack |

Isolated `devsecops-net` network — Juice Shop not exposed directly, only accessible through the WAF on port 8080.

---

## 3. Attack Timeline

| Time | Phase | Action | WAF Result |
|---|---|---|---|
| 09:43:50 | Reconnaissance | Scan for sensitive paths (`/admin`, `/.git/config`) | 200 (Juice Shop SPA absorbs) |
| 09:44:03 | SQLi | `OR '1'='1` | **403 Blocked** |
| 09:44:06 | SQLi | `UNION SELECT null,null,null--` | **403 Blocked** |
| 09:44:12 | SQLi | `DROP TABLE users;--` | **403 Blocked** |
| 09:44:20 | XSS | `<script>alert('XSS')</script>` | **403 Blocked** |
| 09:44:26 | Encoded XSS | `%3Cscript%3Ealert%281%29` | **403 Blocked** |
| 09:44:31 | Path Traversal | `../../../../etc/passwd` | **403 Blocked** |
| 09:44:45 | False Positive | `O'Reilly` (legitimate search) | 200 (OK) |

---

## 4. Log Analysis (LogQL)

**Block Detection Query:**
```logql
{job="waf"} |= "403"
```

**Observation:** Spike of 403s between 09:44:00 and 09:45:00 exactly matching the attack simulation. All legitimate requests (200) continued to pass normally — no service interruption.

---

## 5. Identified False Positive

**Symptom:** WebSocket connections from Juice Shop to `/socket.io/` were receiving HTTP 403. The app lost its real-time connection.

**Root Cause:** The parameters `EIO`, `transport` and `sid` in the Socket.IO URL triggered the CRS rule `REQUEST-920-PROTOCOL-ENFORCEMENT` (anomaly score too high).

**Remediation:**
```nginx
SecRule REQUEST_URI "@beginsWith /socket.io/" \
    "id:1001,phase:1,pass,nolog,\
    ctl:ruleEngine=DetectionOnly,\
    msg:'Exclusion socket.io - legitimate Juice Shop traffic'"
```

Deployed via Ansible (`waf-setup.yml`) — idempotent and versioned.

**Post-remediation verification:**
```bash
curl http://localhost:8080/socket.io/?EIO=4&transport=polling → 200 ✅
curl "http://localhost:8080/rest/products/search?q=UNION SELECT" → 403 ✅
```

---

## 6. Database Hardening

In parallel with WAF analysis, the `db-hardening.yml` playbook applied CIS Benchmark MySQL 8.0 controls:

- Removal of anonymous users
- Root restricted to localhost connections only
- Password policy (validate_password MEDIUM, 12 characters)
- SSL/TLS enabled (`require_secure_transport = ON`)
- Disabled `local-infile` and `symbolic-links`
- Creation of application user with minimal privileges

---

## 7. Recommendations

**Short-term:**
- Enable ModSecurity audit logging (`/var/log/modsec_audit.log`) for detailed rule-triggered information by ID
- Configure Grafana alert on `count_over_time({job="waf"} |= "403" [1m]) > 10`

**Medium-term:**
- Replace Terraform secrets (`terraform.tfvars`) with Podman Secrets or dedicated secret manager
- Pin image versions (avoid `:latest` in production)

**Long-term:**
- Integrate SIEM (Wazuh) to correlate WAF events with other log sources
- Implement CI/CD pipeline that runs `site.yml` on each commit (GitOps)

---

## 8. Conclusion

The DevSecOps infrastructure deployed in IaC (Terraform + Ansible) demonstrates effective application protection. The WAF blocks the most common OWASP Top 10 attack vectors while allowing false-positive tuning through versioned exception rules. The observability chain Promtail → Loki → Grafana enables near-real-time detection and analysis.