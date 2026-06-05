## What & Why
<!-- 1-3 sentences describing the change and the motivation. -->

## Risk classification (check exactly one)

- [ ] No risk (docs, comments, internal tooling only)
- [ ] Low (refactor with no behavior change)
- [ ] Medium (behavior change with no security / PHI / PII surface change)
- [ ] **High** (touches auth, PHI/PII, encryption, IAM, networking, secrets, or audit logs)

## PHI / PII impact

- [ ] No PHI/PII added, modified, or exposed by this change
- [ ] Touches PHI/PII — describe what data and how it remains protected:

## Test plan

- [ ] Unit tests added / updated
- [ ] Integration tests pass
- [ ] Manual verification steps (if any):

## Rollback plan

<!-- How do we revert this in production if it breaks? -->

## Security review

- [ ] Not required (Low / No risk)
- [ ] Requested — auto-required for High risk; reviewer assigned via CODEOWNERS

## Linked work

<!-- Linear ticket; related PRs; design doc. -->
