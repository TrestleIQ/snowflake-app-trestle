# snowflake-app-trestle: architecture & operations context

Deep context for this repo. Start with `CLAUDE.md` for the short version.

## 1. What this is

A **Snowflake Native App** that Trestle publishes to Snowflake customers. Once installed in a
customer's own Snowflake account, it lets them run **Trestle Phone Validation** on phone numbers in
their tables with plain SQL. Customers bring their own Trestle API key.

## 2. Runtime flow (customer side)

```
Customer's Snowflake account
  SELECT * FROM TABLE(<app>.code_schema.validate_phone((SELECT ARRAY_AGG(phone) FROM t)));
     │
     ▼
  Python UDTF  (app/src/udf1.py, RUNTIME_VERSION 3.14)
     • reads the API key from the consumer SECRET reference  (CONSUMER_SECRET)
     • egress allowed only to api.trestleiq.com            (CONSUMER_EXTERNAL_ACCESS)
     • per phone: GET https://api.trestleiq.com/3.0/phone_intel?phone=<n>  (header x-api-key)
     • yields (phno, data VARIANT)
     ▼
  Trestle API  (billed against the customer's own key)
```

| File | Role |
|---|---|
| `phone_validation/app/manifest.yml` | Declares the two consumer references: `CONSUMER_SECRET` (READ) and `CONSUMER_EXTERNAL_ACCESS` (USAGE, required at setup) |
| `phone_validation/app/setup_script.sql` | Runs on install/upgrade: app role `app_public`, schemas `core` and `code_schema` (versioned), reference callbacks, and `code_schema.create_eai_objects()` |
| `code_schema.create_eai_objects()` | Creates `code_schema.validate_phone(ARRAY)` **when the customer calls it**, not at install. Customers must re-run it after upgrades that change the function (e.g. runtime). |
| `phone_validation/app/src/udf1.py` | UDTF handler `udf1.validate_phone` (`udf.py` is unused) |
| `phone_validation/snowflake.yml` | Snowflake CLI project: package `TRESTLE_VALIDATE_PHONE_PACKAGE`, dev app `TRESTLE_VALIDATE_PHONE` |

**Inter-service call:** consumer Snowflake → `api.trestleiq.com/3.0/phone_intel` (public Trestle API).
No Trestle DB tables, SQS queues, S3/FSx paths or internal services are involved.

## 3. Provider-side Snowflake objects (account WYNRKMV-CWB34849)

| Object | Type | Owner | Purpose |
|---|---|---|---|
| `TRESTLE_VALIDATE_PHONE_PACKAGE` | Application package, **EXTERNAL** | ACCOUNTADMIN | **Production.** Versions/patches + the `DEFAULT` release directive customers receive |
| `TRESTLE_VALIDATE_PHONE` | Application (dev mode) | ACCOUNTADMIN | Human pre-release check on the prod package |
| `TRESTLE_VALIDATE_PHONE_PACKAGE_CI` | Application package, INTERNAL | APP_DEPLOYER | **CI only.** Never versioned or released |
| `TRESTLE_VALIDATE_PHONE_CI` | Application (dev mode) | APP_DEPLOYER | CI test install |
| `APP_DEPLOYER` | Role (granted to SYSADMIN) | — | CI role: USAGE on `COMPUTE_XS`, CREATE APPLICATION PACKAGE, CREATE APPLICATION, plus ownership of the `_CI` objects it created. **No privileges on the prod package.** |
| `SVC_SNOWFLAKE_APP_CI` | User, `TYPE=SERVICE` | — | CI identity. No password, no MFA; RSA key-pair (JWT) auth only. Default role `APP_DEPLOYER`. |

## 4. CI (`.github/workflows/deploy.yml`) — TRES-7206

Triggers: push to `main`, PRs to `main`, manual dispatch.

1. **`build`** (offline): `py_compile` the handlers, `snow app bundle`. No Snowflake login.
2. **`validate`**: runs in GitHub environment **`snowflake-ci`** (required reviewers must approve
   each run; self-approval is blocked). Fork PRs skip it. One run at a time (`concurrency`).
   - writes the private key to `$RUNNER_TEMP` (mode 600), deleted in an `always()` step
   - generates a git-ignored `snowflake.local.yml` that retargets the project to the `_CI` package/app
   - `snow connection test` → `snow app validate` → `snow app run --no-validate --force`, all as
     `SVC_SNOWFLAKE_APP_CI` / `APP_DEPLOYER` with `--authenticator SNOWFLAKE_JWT`
3. **`notify`**: on PR failure, comments on the PR (only job with `pull-requests: write`).

Environment secrets (`snowflake-ci`): `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`,
`SNOWFLAKE_CI_PRIVATE_KEY` (encrypted PKCS#8), `SNOWFLAKE_CI_PRIVATE_KEY_PASSPHRASE`.
Snowflake CLI: `snowflake-cli==3.34.0`; Python 3.12 on the runner.

**CI never runs `snow app version create` or `snow app release-directive set`.** Even if someone added
them, Snowflake would reject them: `APP_DEPLOYER` cannot see the prod package.

## 5. Why CI uses a separate `_CI` package (and not the prod package)

Deliberate (TRES-7206), to keep "release stays manual" **enforced by Snowflake**, not by convention:

1. **Uploading into prod effectively means owning prod.** Writing to the prod package's stage needs
   ownership-level rights, and ownership also allows creating versions and setting the release
   directive.
2. **Unmerged PR code would sit in the prod package.** CI runs on every PR. If it uploaded to prod, the
   prod stage would hold the last PR's code, and a `version create` without re-uploading would ship
   unreviewed branch code. The pre-TRES-6938 CI did exactly this, and also set the release directive
   on PRs because of a swapped condition.
3. **Blast radius.** The repo is public. A leaked CI key can only affect the throwaway `_CI` copy, never
   customers.

Cost: the release manager uploads to prod themselves (step 2 below).

## 6. Releasing to customers (manual, human-run)

Run from an up-to-date `main` checkout, as an ACCOUNTADMIN user with your own MFA / browser-auth
connection (`authenticator = externalbrowser`). Never from CI.

1. `cd phone_validation && rm -rf output app/src/__pycache__`
2. `snow app run -c <your-connection>` — uploads `main` to the prod package and upgrades the dev app
   `TRESTLE_VALIDATE_PHONE`.
3. Manual functional test in a test install: `CALL code_schema.create_eai_objects();` then call
   `validate_phone` on a few numbers with a real API key (CI cannot do this; see §7).
4. `snow app version create V1 -c <your-connection>` — adds the next patch to V1 (note the patch
   number). EXTERNAL packages go through Snowflake's security review; wait for `APPROVED`
   (`SHOW VERSIONS IN APPLICATION PACKAGE TRESTLE_VALIDATE_PHONE_PACKAGE;`).
5. `snow app release-directive set default --version V1 --patch <n> -c <your-connection>` —
   **the customer-facing switch.** Get sign-off first.

`docs/TRES-6938-handover.md` has a full worked example (V1 patch 10).

## 7. What a green CI run does and does not prove

Proves: handlers compile; bundle builds; the service user can log in with the key; the setup script
and manifest are valid; the app installs/upgrades cleanly (in the `_CI` copy).

Does **not** prove: the body of `create_eai_objects()` (runtime version, packages, handler name) —
it only runs when a customer calls it; runtime logic in `udf1.py`; real calls to `api.trestleiq.com`
(the CI app has no key/EAI); Snowflake's security review of a new EXTERNAL version.

## 8. When CI fails

| Where | Typical cause |
|---|---|
| `build` | Python syntax error; invalid `manifest.yml` / `snowflake.yml`; missing app files; PyPI outage |
| `validate` → `snow connection test` | Key unset/rotated in Snowflake but not in GitHub (`JWT token is invalid`); wrong passphrase; user disabled; a network policy blocking GitHub IPs; `APP_DEPLOYER` grants or `COMPUTE_XS` changed |
| `validate` → `snow app validate` / `run` | SQL error in `setup_script.sql`; bad manifest reference; upgrade of the existing `_CI` app fails |

Not failures: no approval yet (job waits; GitHub cancels after 30 days); fork PR (job skipped);
concurrent run (queued).

## 9. Key rotation

Needs a repo admin and a Snowflake ACCOUNTADMIN.

1. Admin, on their own machine: generate an encrypted RSA key with a random passphrase and pipe both
   straight into the `snowflake-ci` secrets with `gh secret set`, print only the public key +
   SHA256 fingerprint, delete the local files.
2. ACCOUNTADMIN: `ALTER USER SVC_SNOWFLAKE_APP_CI SET RSA_PUBLIC_KEY = '<pub>';` (whichever of
   `RSA_PUBLIC_KEY` / `RSA_PUBLIC_KEY_2` is empty — currently slot 1), then check
   `DESC USER` shows the matching `*_FP` fingerprint.
3. Run CI; once green, `ALTER USER SVC_SNOWFLAKE_APP_CI UNSET RSA_PUBLIC_KEY_2;` (the old slot).

Never commit a `.p8`. Never paste private keys or passphrases into chat, tickets or logs.

## 10. History

- **TRES-6938** — Python runtime 3.9 → 3.14 (V1 patch 10). Removed the shared human
  password login from CI after Snowflake made MFA mandatory; CI became offline-only.
- **TRES-7206** — CI validate/test-deploy restored via `SVC_SNOWFLAKE_APP_CI` key-pair auth against the
  `_CI` package; release stays manual (PR #6).
