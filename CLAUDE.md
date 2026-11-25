# snowflake-app-trestle

Snowflake Native App that lets Snowflake customers run Trestle Phone Validation
(`GET https://api.trestleiq.com/3.0/phone_intel`) on phone numbers in their own tables.

## Layout
- `phone_validation/snowflake.yml` — Snowflake CLI project: package `TRESTLE_VALIDATE_PHONE_PACKAGE`, test app `TRESTLE_VALIDATE_PHONE`
- `phone_validation/app/manifest.yml` — references the customer grants: `CONSUMER_SECRET` (API key), `CONSUMER_EXTERNAL_ACCESS` (EAI to api.trestleiq.com)
- `phone_validation/app/setup_script.sql` — runs on install/upgrade; `code_schema.create_eai_objects()` creates the UDTF
- `phone_validation/app/src/udf1.py` — UDTF handler (`udf1.validate_phone`); `udf.py` is unused

## Runtime & Stack
- Python UDTF `code_schema.validate_phone(ARRAY)`, handler `src/udf1.py`
- Python runtime: 3.14 — set only in `app/setup_script.sql` (`RUNTIME_VERSION`)
- Packages (Snowflake Anaconda channel): snowflake-snowpark-python, requests
- The function is created inside `create_eai_objects()`, not by the setup script itself. Changing the
  runtime requires customers to re-run `call code_schema.create_eai_objects();` after upgrading.

## Build (local, no Snowflake connection)
```bash
cd phone_validation
rm -rf output app/src/__pycache__ \
 && python3 -m py_compile app/src/udf1.py app/src/udf.py \
 && snow app bundle
```
`snowflake.yml` uploads `app/*`, so delete `app/src/__pycache__` before any deploy.

## CI / Deploy
- `.github/workflows/deploy.yml` installs `snowflake-cli==3.34.0` (the old `snowflake-cli-labs==3.4.1`
  + `click<8.2` pin is gone).
- `build` job: offline — compile handlers + `snow app bundle`. No Snowflake login.
- `validate` job (TRES-7206): logs in to WYNRKMV-CWB34849 as `SVC_SNOWFLAKE_APP_CI` (`TYPE=SERVICE`,
  key-pair / `SNOWFLAKE_JWT`, role `APP_DEPLOYER`) and runs `snow app validate` + `snow app run` against
  the CI-only `TRESTLE_VALIDATE_PHONE_PACKAGE_CI` / `TRESTLE_VALIDATE_PHONE_CI`, via a generated
  (git-ignored) `snowflake.local.yml`. Gated by the `snowflake-ci` GitHub environment (required
  reviewers), which holds `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_CI_PRIVATE_KEY`,
  `SNOWFLAKE_CI_PRIVATE_KEY_PASSPHRASE`. Fork PRs skip this job.
- `APP_DEPLOYER` has only: USAGE on `COMPUTE_XS`, CREATE APPLICATION PACKAGE, CREATE APPLICATION. It has
  **no** privileges on the prod package `TRESTLE_VALIDATE_PHONE_PACKAGE` — don't grant any.
- **Releasing stays manual**: `snow app version create` / `snow app release-directive set default` on the
  prod package, run locally as ACCOUNTADMIN via `authenticator=externalbrowser`. Never add these to CI.
- The repo is public: Actions logs are public, so don't add debug output to the `validate` job.
- Key rotation (needs a repo admin): the admin generates a new encrypted key pair locally, pipes the
  private key + passphrase straight into the `snowflake-ci` secrets with `gh secret set`, and deletes the
  local files. An ACCOUNTADMIN then sets the public key in the free slot
  (`ALTER USER SVC_SNOWFLAKE_APP_CI SET RSA_PUBLIC_KEY[_2] = '...'`), checks the `RSA_PUBLIC_KEY*_FP`
  fingerprint, and once CI is green `UNSET`s the old slot. Never commit a `.p8`.
