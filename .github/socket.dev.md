# Socket.dev — not enabled (decision record)

**Socket.dev** is a supply-chain security tool that analyzes dependency *behavior* (install scripts, network/filesystem access, obfuscation, new/changed maintainers, typosquatting) to catch **malicious packages before any CVE exists**.

## How it works
- Runs on pull requests that change dependency manifests (`go.mod`, `package.json`, `requirements.txt`, etc.).
- Posts a PR comment flagging risky/malicious dependency changes.

## How it differs from what we already run
- **Dependabot + govulncheck / pip-audit / npm audit / OWASP dependency-check** catch **known CVEs** and ship update PRs.
- **gitleaks** catches committed secrets.
- **Socket** catches **unknown / zero-day malicious packages** (behavioral), which CVE scanners miss.

## Why it is not enabled
- Paid SaaS, billed **per developer** (contributors to the monitored repos, not per PR-merger), plus a `SOCKET_SECURITY_API_KEY` org secret.
- **Not required** for SOC 2 / HIPAA. We rely on the free CVE + secret + SAST stack above for now.
- **Accepted residual gap:** behavioral supply-chain detection has no free equivalent (Snyk, Phylum, Endor Labs are also paid; OSV-Scanner is CVE-based only).

## To enable later
1. Provision an account at socket.dev and add `SOCKET_SECURITY_API_KEY` as an org-level GitHub secret.
2. Add a `socket-scan.yml` triggered on dependency-manifest changes (skip Dependabot-authored PRs).
