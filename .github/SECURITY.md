# Security Policy

SensorBio takes the security of our platform and the protection of the health
data entrusted to us seriously. We welcome reports from security researchers and
will work with you in good faith to validate and resolve legitimate findings.

## Scope

SensorBio operates a hosted platform together with a set of client SDKs and
applications. This policy covers SensorBio-owned code in this organization's
repositories and our production services. We maintain the currently deployed
production version of the platform and the actively supported release lines of
our SDKs.

## Reporting a vulnerability

Please report suspected vulnerabilities **privately**. Do **not** open a public
GitHub issue, and please give us a reasonable opportunity to remediate before any
public disclosure.

- **Email:** `security@sensorbio.com`
- **Acknowledgement:** we aim to acknowledge your report within **3 business days**.
- **Assessment:** we aim to provide an initial assessment within **10 business days**
  and to keep you updated on remediation progress for valid findings.
- **Coordinated disclosure:** we follow a **90-day** coordinated-disclosure timeline
  by default, and are glad to coordinate timing with you — including a reasonable
  extension when a fix legitimately needs more time.
- **Safe harbor:** we will not pursue or support legal action against researchers
  who act in good faith, follow this policy, and avoid privacy violations and
  service disruption.

## What to include

- A description of the vulnerability and its potential impact.
- Clear steps to reproduce (a proof-of-concept or minimal test case helps a lot).
- Your contact details — optional; anonymous reports are accepted.

## Testing guidelines

Because we handle personal health data, please:

- Use **test accounts and test data only**. Do not access, modify, store, or
  exfiltrate other people's data or any real personal/health information.
- Do not run automated scanners, fuzzing, or load/denial-of-service testing
  against our production systems.
- Stop immediately and report to us if you encounter any personal or health data.

## Out of scope

- Self-XSS, clickjacking on pages without sensitive actions, and missing security
  headers with no demonstrated, exploitable impact.
- Vulnerabilities in third-party services we use — please report those to the vendor.
- Denial-of-service and volumetric attacks.
- Social engineering of SensorBio staff, customers, or vendors.
- Automated-tool output without a demonstrated, validated impact.

Thank you for helping keep SensorBio and the people who rely on us safe.
