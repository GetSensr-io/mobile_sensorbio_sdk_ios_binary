# CodeQL — not enabled in this repo

GitHub CodeQL (deep semantic SAST) is intentionally **not** enabled here.

## Why
- On **private** repos, CodeQL code scanning requires **GitHub Advanced Security**, which requires **GitHub Enterprise**. We are on **GitHub Team**, so it can't run on private repos.
- For **embedded C/C++** repos it also needs a cross-compile build that won't run on a stock runner.
- To keep every repo in sync, CodeQL is off **everywhere** for now (including public repos).

## What covers SAST instead (all free, in `security.yml`)
- **semgrep** — multi-language rulesets; the closest CodeQL alternative.
- Language SAST: **gosec** (Go) / **bandit** (Python) / **detekt** (Kotlin) / **SwiftLint** (Swift) / **cppcheck** (C/C++).
- **gitleaks** (secrets) + dependency scanning (**govulncheck** / **pip-audit** / **npm audit** / **OWASP dependency-check**).

## To enable CodeQL later
1. Either make the repo **public** (CodeQL is free for public repos), or upgrade to **GitHub Enterprise + Advanced Security**.
2. Add a `codeql.yml` (copy from a same-language repo) and, for compiled languages, wire the real build.
