# Sensor Bio Product-Loop Backend — Ownership & Access Map

Task: t_26857dad — Identify Sensor Bio backend repo ownership and verify access.
Prepared: 2026-07-09. Author: coder (kanban worker), acting as GitHub `sontakey`.
Scope: locate where the product-loop backend (Personal Insights, processed
sleep/Recovery metrics, notifications, device registration) lives, confirm it is
server-side (not the iOS client), and verify working access + credentials.

**No implementation was done in this task. Findings only.**

---

## 1. TL;DR

- The product-loop backend is **server-side**, not in this iOS binary repo. It
  lives in the GitHub org **`GetSensr-io`**, primarily in the Go monolith
  **`server_svc_core_api_monolith`**.
- This workspace (`mobile_sensorbio_sdk_ios_binary`) is a **public binary
  distribution of the iOS SDK** — a client artifact, NOT where Personal
  Insights / Recovery / notifications are computed. Confirmed the correct
  backend home is the monolith below.
- **Access is CONFIRMED GOOD** on every backend repo required: clone + push +
  admin on the monolith, infrastructure (AWS IaC), web platform, sleep-report,
  pdfreports, protos, lambdas, pyworker. See §5.
- Acceptance criterion (a) satisfied by this document; (b) satisfied — all
  required repos show `push=true, admin=true`. No BLOCKED items for repo/clone
  access. One caveat on cloud/staging **runtime** credentials — see §6.

---

## 2. Which repo owns the product loop

Org `GetSensr-io` has ~50 repos. The relevant backend/product-loop repos:

| Repo | Lang | Vis | Role in the product loop |
| --- | --- | --- | --- |
| **`server_svc_core_api_monolith`** | Go | private | **Primary backend.** gRPC + REST + scheduled workers/crons. Owns Personal Insights, daily scores (Recovery/Activity), sleep processing, push/in-app notifications, device subscriptions. PHI/PII data plane, HIPAA + SOC 2 in scope. Default branch `develop`. |
| `infrastructure` | HCL/Terraform | private | AWS IaC — EKS, ECR, environments (legacy prod/staging/shared + `new/kubernetes-managed`). Canonical org-wide governance: ADRs (`compliance/decisions/ADR-00x`), AGENTS.md, deploy/staging policy. |
| `mobile_grpc_protos` | protobuf/Ruby | private | Shared gRPC proto definitions (`specs/proto` symlinked into the monolith as `proto`). Source of truth for mobile↔backend contracts. |
| `web_platform` | TypeScript | private | Web dashboard / org-facing platform frontend. Consumer of the monolith API. |
| `sensorbio-sleep-report` | TS (Next.js) | private | Standalone sleep-report web app. Default branch `master`. Presentation layer, not the metric owner. |
| `server_svc_pdfreports` | TypeScript | private | PDF report generation microservice (monthly/compliance report rendering). |
| `server_awslambdas` | — | private | Serverless lambda functions (auxiliary backend). |
| `server_svc_pyworker` | — | private | Python worker service (auxiliary async processing). |
| `log-debug-agent` | Python | private | Ops/log-debug tooling. |

**Client repos (NOT backend, for contrast):**
`mobile_sensorbio_sdk_ios_binary` (this workspace, public), `mobile_app_ios`,
`mobile_app_android`, `mobile_sensorbio_sdk_ios`/`_android` (base-layer SDKs),
edge/bluetooth SDKs, firmware repos. These consume the backend; they do not own
Insights/Recovery/notification logic.

---

## 3. Service boundaries inside the monolith (`server_svc_core_api_monolith`)

Layout: `api/` (endpoints), `pkg/` (domain packages), `go-workers/` (async),
`go-crons/` (scheduled), `db/` (schema + migrations), `devops/` (Ansible +
CodeDeploy), `specs/proto` (gRPC).

Product-loop domains mapped to `pkg/` + workers/crons:

| Product-loop concern | Owning packages | Workers / crons |
| --- | --- | --- |
| **Personal Insights** | `pkg/insightsgenerator` (population_insights, population_metrics_meta), `pkg/coachinginsights` | `go-workers/orginsightsgen`, `go-workers/coaching_insights`, `go-crons/coaching_insights_scheduler` |
| **Recovery / daily scores** | `pkg/dailyscores` (`recovery_score.go`, `RECOVERY_SCORE.md`, `ACTIVITY_SCORE.md`, `customscorealgorithm/`), `pkg/smart_metrics`, `pkg/statscalc` | `go-workers/dailystatsaggregation`, `go-workers/smartmetrics`, `go-crons/cache_dailymetrics`, `go-crons/statscache_updater` |
| **Sleep (processed metrics)** | `pkg/sleep`, `pkg/sleepflowanalysis`, `pkg/sleepjobtracking` | `go-workers/sleep_processing`, `go-workers/sleep_recommendations` |
| **Notifications** | `pkg/pushnotification` (pushservice, repo, conv), `pkg/inappnotification`, `pkg/messaging`, `pkg/email` | `go-workers/pushnotifications`, `go-workers/emailworkers`, `go-workers/org_pushnotifications_reminders`, `go-crons/pushnotification_checkr` |
| **Device registration / subscriptions** | `pkg/device_subscriptions` (QR-code service, repo, lib), `pkg/firmware`, `pkg/accountsvc`, `pkg/users` | `go-crons/device_subscription_expiry_updater`, `go-workers/accountsvc` |
| **Reports (context)** | `pkg/monthlyreport`, `pkg/pulsereport`, `pkg/compliancereport` | `go-workers/monthlyreports`, `go-crons/monthlyreport_requestr`, `go-crons/compliancereport` |

Recovery Score is a daily 0–100 metric computed each morning after a sleep
session from wearable biometrics vs a personal 30-day baseline (needs ≥4 prior
days of sleep/HRV/RHR). Fully server-side — confirms the product loop is NOT in
the iOS client. (Source: `pkg/dailyscores/RECOVERY_SCORE.md`.)

---

## 4. Migrations & deployment policy (work-scoped)

**Migrations:** golang-migrate against **Aurora MySQL**. Migration files in
`db/aurora_migrations/` (~525 versioned migrations). Run by a standalone
migrate binary via the **AWS CodeDeploy AfterInstall hook** —
`devops/codedeploy/appspec.migration.yaml.template` +
`scripts/run-db-migrate.sh.template` (+ `validate-db-migrate.sh.template`).
`db.NewDB(runMigration, ...)`'s `runMigration` flag is deprecated — the app no
longer runs migrations inline; always pass `false`. Local dev uses
`go-scripts/cmd/migrate_local_mysql` against `localhost:23306`.

**CI merge gates** (`.github/workflows/`): `build.yml` (go build ./... + gofmt +
vet + mod tidy drift), `test.yaml` (test suite), `security.yml`,
`container-scan.yml`, `release-sbom-license.yml`. Triggered on PRs and pushes to
`develop`/`main`/`master`/`prod`/`production`. Intended required checks to be
wired via SB-892 branch protection (not yet fully applied — see §7).

**Deploy / staging policy:** explicit `make` targets per artifact + environment,
delegating to `devops/ansible`:
- `make deploy-api-service-staging` / `-prod`
- `make deploy-crons-staging` / `-prod`
- `make deploy-workers-staging` / `-prod`
- `make deploy-tools-swissknife-staging` / `-prod`
- developer API/SDK docs: `deploy-developers-*-staging` / `-prod` (S3)

`DEPLOY_ENV?=dev`; `buildAndDeploy.sh` builds api + `make deploy-api` to the dev
server. A dedicated **staging** environment exists (Terraform
`infrastructure/legacy/environments/staging/` + `new/kubernetes-managed/.../
environments`). Work-scoped policy: staging deploys are allowed via the
`*-staging` make targets; production requires the `develop` → release-PR cycle.

**Branch/permission rules (from monolith `AGENTS.md`):** default branch
`develop`; ticket branches off `develop` via worktree
(`.claude/worktrees/<TICKET>`). Never commit/push/merge/rebase/force-push or post
outward-facing GitHub writes (PR reviews/comments/merge) without explicit
per-request approval. No agent attribution in commits/PRs. Never commit secrets.

---

## 5. Access verification (as GitHub `sontakey`)

`gh auth`: logged in as **`sontakey`**, scopes `repo, read:org, workflow, gist`,
HTTPS. Per-repo permissions via `gh api repos/GetSensr-io/<repo>`:

| Repo | pull | push | admin | Clone tested |
| --- | --- | --- | --- | --- |
| `server_svc_core_api_monolith` | ✓ | ✓ | ✓ | ✓ cloned (depth 1) OK |
| `infrastructure` | ✓ | ✓ | ✓ | api tree read OK |
| `web_platform` | ✓ | ✓ | ✓ | — |
| `sensorbio-sleep-report` | ✓ | ✓ | ✓ | contents read OK |
| `server_svc_pdfreports` | ✓ | ✓ | ✓ | — |
| `mobile_grpc_protos` | ✓ | ✓ | ✓ | — |
| `server_awslambdas` | ✓ | ✓ | ✓ | — |
| `server_svc_pyworker` | ✓ | ✓ | ✓ | — |
| `log-debug-agent` | ✓ | ✓ | ✓ | — |

**Repo/CI/clone/push access: CONFIRMED for every required repo.** `workflow`
scope present → can manage GitHub Actions. Admin on the monolith → can manage
branch protection / required checks if SB-892 work lands here.

---

## 6. Cloud / staging runtime credentials — caveat (NOT a hard block for THIS task)

This task only needed to *verify access to repos + confirm the deploy path
exists*, which is done. However, actually running a staging **deploy or DB
migration** at implementation time additionally requires runtime credentials
that are NOT part of GitHub repo access and were NOT exercised here:

- **AWS credentials** for the SensorBio account (CodeDeploy, EKS/ECR, Aurora,
  S3, Ansible SSH to VMs). Source of truth: `infrastructure` repo + AWS SSO/IAM.
  Not verified in this task (no AWS calls made).
- **Aurora MySQL staging DSN / secrets** (pulled from AWS Secrets Manager / env
  at deploy time, not from the repo).
- **Ansible inventory / SSH keys** for staging VMs (referenced by
  `devops/ansible`).

These are expected to be provisioned via AWS SSO + Secrets Manager, not stored
in git. **Recommendation for the implementation task:** before first staging
deploy, confirm AWS SSO login works for the SensorBio account and that
`make deploy-*-staging` can reach staging. If AWS access is missing, that is the
item to escalate (grantor: whoever owns the SensorBio AWS org / infrastructure
repo admins).

---

## 7. Known repo-status caveats (from monolith AGENTS.md, June 2026)

- **SB-890 (CI/CD security baseline):** uncommitted in an SB-890 worktree; this
  repo is in the **secret-hold cohort** (committed secrets — Slack webhooks,
  Intercom secret, TLS private keys under `sslcert/`, assorted API keys — must
  be rotated + removed before the baseline lands). Rotation is user-driven.
- **SB-892 (branch protection):** not yet applied here; only default GitHub
  protection (PR required, no force-push to `develop`) is in effect.
- Treat `devops/ansible/` (runs on prod VMs) and `non-go-code/` as sensitive
  paths.

---

## 8. Conclusion

- Product-loop backend home: **`GetSensr-io/server_svc_core_api_monolith`** (Go),
  supported by `infrastructure`, `mobile_grpc_protos`, and the TS services.
  Server-side confirmed; the iOS binary repo is only a client artifact.
- **Access: GOOD.** Full clone/push/admin on all required backend repos; CI
  visible; staging deploy path (`make deploy-*-staging` → Ansible/CodeDeploy)
  and migration mechanism (golang-migrate → Aurora via CodeDeploy AfterInstall)
  documented.
- **Only open item** for the eventual implementation phase: verify AWS/staging
  *runtime* credentials (SSO, Secrets Manager, Ansible SSH) — out of scope for
  this repo-ownership task, flagged here so the build task starts unblocked.
