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
- `.github/workflows/deploy.yml` installs `snowflake-cli-labs==3.4.1` with `click<8.2`.
  click ≥ 8.2 crashes CLI 3.4.1 on startup (`make_metavar() missing 'ctx'`). Remove the
  pin only when upgrading the CLI (current package name: `snowflake-cli`).
- PR runs deploy (`snow app run`) and set the default release directive in account WYNRKMV-CWB34849.
- On `main`, `snow app version create` is commented out — releasing a new version is manual.
