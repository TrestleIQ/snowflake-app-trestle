# TRES-6938 — Handover: Upgrade Snowflake app to a newer Python version

| | |
|---|---|
| **Ticket** | [TRES-6938](https://trestleiq.atlassian.net/browse/TRES-6938) — Upgrade Snowflake app to newer Python version |
| **Repo** | `snowflake-app-trestle` |
| **Owner** | Shivani Singh |
| **Last updated** | 2026-10-26 |
| **Status** | Code change done and locally verified. **Snowflake testing not started** (account access being sorted out). Not committed, no PR. |

---

## 1. TL;DR

- Snowflake **decommissioned Python 3.9 on 30 Apr 2026**. Our app creates its `validate_phone` function on 3.9, so **new installs are most likely failing at the setup step today**. Existing installs still run, but on an unpatched runtime.
- Fix: one line in `phone_validation/app/setup_script.sql`, from `RUNTIME_VERSION = '3.9'` to `'3.14'`.
- Local checks pass: the Python compiles on 3.14, the Native App bundle builds, and the bundle contains `'3.14'`.
- **Existing customers must re-run `CALL code_schema.create_eai_objects();` after upgrading.** This was found by reading the code; the upgrade test still needs to confirm it.
- Remaining: test in Snowflake (AC1–AC4), commit, PR (needs repo write access), and release (manual).

---

## 2. Background

### What the app does
`snowflake-app-trestle` is a **Snowflake Native App**. Customers install it into **their own** Snowflake account and run Trestle Phone Validation (`GET https://api.trestleiq.com/3.0/phone_intel`) on phone numbers already in their tables, without exporting the data.

### Customer flow
1. Install the app from the listing. Snowflake runs `setup_script.sql`, which creates the schemas and procedures but **not** the function.
2. In Snowsight, under **Security → Connections**, add the Trestle API key as a **Secret** and approve the **External Access Integration** for `api.trestleiq.com`.
3. Run `CALL code_schema.create_eai_objects();`. This creates the Python UDTF `code_schema.validate_phone(ARRAY)`.
4. Query it:
   ```sql
   select * from table(<APP_NAME>.code_schema.validate_phone(
     (select array_agg(phone) from <their_table>)));
   ```
   This returns `phno` and `data` (the full API JSON) per number. Each number is one API call, billed against the customer's Trestle plan.

### How Python fits in
The handler `app/src/udf1.py` runs **inside Snowflake** (Snowpark Python UDTF). The Python version comes from `RUNTIME_VERSION` in the `CREATE FUNCTION` statement, not from anything installed locally. Packages come from Snowflake's Anaconda channel. `_snowflake` is a Snowflake-only module, used to read the secret.

### Repo files
| File | Purpose |
|---|---|
| `phone_validation/snowflake.yml` | Snowflake CLI project definition: application package `TRESTLE_VALIDATE_PHONE_PACKAGE` and test app `TRESTLE_VALIDATE_PHONE` |
| `phone_validation/app/manifest.yml` | Shipped to customers. Points to the setup script and README, and declares two references the customer must grant: `CONSUMER_SECRET` (READ on a secret) and `CONSUMER_EXTERNAL_ACCESS` (USAGE on an EAI, required at setup). |
| `phone_validation/app/setup_script.sql` | Runs on install and upgrade. Creates roles, schemas, callback procedures, and `create_eai_objects()`, which creates the function. **The Python version is set here.** |
| `phone_validation/app/src/udf1.py` | The handler actually used (`udf1.validate_phone`) |
| `phone_validation/app/src/udf.py` | Not referenced by anything |
| `.github/workflows/deploy.yml` | CI: validate, deploy (`snow app run`), release directive. See §8. |

---

## 3. What we found

### Python runtime status ([Snowflake runtime policy](https://docs.snowflake.com/en/developer-guide/python-runtime-support-policy))
| Runtime | Deprecated | Decommissioned |
|---|---|---|
| 3.9 | 05 Oct 2025 | **30 Apr 2026** |
| 3.10 | 04 Oct 2026 (already deprecated) | TBD |
| 3.11 | 24 Oct 2027 | TBD |
| 3.12 | 02 Oct 2028 | TBD |
| 3.13 | 07 Oct 2029 | TBD |
| **3.14** | 07 Oct 2030 | TBD |

- After decommission: *"you can no longer create or update functions using the runtime"*, but *"existing functions using the runtime can still be invoked."*
- [Snowflake's Python UDF page](https://docs.snowflake.com/en/developer-guide/udf/python/udf-python-introduction) lists 3.10–3.14 as GA. Some older doc snapshots showed 3.14 as preview, so confirm in the account (§6, step 1).

### Package availability (Snowflake Anaconda channel, checked 2026-10-23)
| Package | 3.14 builds |
|---|---|
| `snowflake-snowpark-python` | ✅ up to 1.55.0 |
| `requests` | ✅ up to 2.34.2 |

### Code
- `udf1.py` uses only `requests`, `_snowflake`, `time` and `json`, so nothing is version-specific. No code changes are needed.
- The Python version is set in **one place only** (`setup_script.sql`, line 83).

---

## 4. What we changed

`phone_validation/app/setup_script.sql` (branch `dev-shivani`, **uncommitted**):
```diff
-RUNTIME_VERSION = '3.9'
+RUNTIME_VERSION = '3.14'
```
Nothing else changed.

**Fallback:** if 3.14 isn't available for Native App functions in the target account, change it to `'3.13'`. That still meets the ticket.

---

## 5. Local validation done

| Check | Result |
|---|---|
| Python compile, `udf1.py` + `udf.py`, Python 3.14.7 | ✅ Passed |
| `snow app bundle`, Snowflake CLI 3.30.0 | ✅ Passed, bundle generated in `phone_validation/output/deploy` |
| Bundled `setup_script.sql` has `RUNTIME_VERSION = '3.14'` | ✅ Confirmed |

To re-run it (clean build):
```bash
cd phone_validation
rm -rf output app/src/__pycache__ \
 && python3 -m py_compile app/src/udf1.py app/src/udf.py \
 && ~/snowcli-venv/bin/snow app bundle \
 && grep -q "RUNTIME_VERSION = '3.14'" output/deploy/setup_script.sql \
 && echo "✅ CLEAN BUILD PASSED" || echo "❌ BUILD FAILED"
```
CLI install, one time: `python3 -m venv ~/snowcli-venv && ~/snowcli-venv/bin/pip install snowflake-cli`

**Limits:** these checks don't connect to Snowflake. They don't prove that 3.14 is available to the app, that the SQL runs, or that the function works.

> ⚠️ Delete `app/src/__pycache__/` before any deploy. `snowflake.yml` uploads `app/*`, so a leftover cache folder would be shipped in the package.

---

## 6. Snowflake accounts: current state

| Account | Identifier | Login URL | What we know |
|---|---|---|---|
| **CI / pipeline account** | `WYNRKMV-CWB34849` | `https://app.snowflake.com/wynrkmv/cwb34849` | `deploy.yml` deploys here (user `CHANDRATRESTLE`, role `ACCOUNTADMIN`, warehouse `COMPUTE_XS`, database `TRESTLE`). The app package `TRESTLE_VALIDATE_PHONE_PACKAGE` and test app `TRESTLE_VALIDATE_PHONE` live here. **Shivani has no user here.** |
| **Account Shivani is logged into** | `BZCWZMW-OQB00231` | `https://app.snowflake.com/bzcwzmw/oqb00231` | A different organization. Contents, role and grants are **unknown**. It probably doesn't have our app, package, `TRESTLE` database or `COMPUTE_XS`. **Open question:** is this the intended test account? |

- **Don't use the CI login (`CHANDRATRESTLE`).** It's a personal `ACCOUNTADMIN` user, and sharing it breaks SOC 2 traceability. Each tester needs their own user.
- Never put passwords in this repo, tickets or chat.

### Next steps in `BZCWZMW-OQB00231`
1. **Find out what access you have** (Snowsight → Worksheet):
   ```sql
   select current_organization_name(), current_account_name(), current_region(), current_role();
   show databases;
   show warehouses;
   show grants to role identifier(current_role());
   ```
   You need: a warehouse, plus `CREATE APPLICATION PACKAGE` and `CREATE APPLICATION` (to deploy a test copy), plus the ability to approve an External Access Integration.
2. **Package check** (select any database and warehouse first):
   ```sql
   select package_name, version from information_schema.packages
   where language = 'python' and runtime_version = '3.14'
     and package_name in ('snowflake-snowpark-python', 'requests')
   order by package_name, version desc;
   ```
   Both packages should appear. If not, re-run with `'3.13'`.
3. **What this account can and can't test:**

   | Test | In `BZCWZMW-OQB00231` |
   |---|---|
   | Package availability | ✅ |
   | `snow app validate`, fresh install (AC1, AC3) | ✅ if you have the grants above. Deploy a **separately named** test copy (see below). |
   | Upgrade an existing 3.9 install (AC4) | ❌ No 3.9 install exists there, and a new one can't be created. Needs the CI account. |
   | Compare results with 3.9 (AC2) | ❌ Same reason. Compare against direct API calls for the same numbers instead. |

4. **CLI connection** (after browser login and MFA work):
   ```bash
   ~/snowcli-venv/bin/snow connection add      # account BZCWZMW-OQB00231, your user, your role/warehouse
   chmod 0600 ~/.snowflake/config.toml
   ~/snowcli-venv/bin/snow connection test -c <connection_name>
   ```
   To deploy a test copy without reusing the production names, create an untracked `phone_validation/snowflake.local.yml` that overrides the identifiers (e.g. `TRESTLE_VALIDATE_PHONE_PACKAGE_DEV` / `TRESTLE_VALIDATE_PHONE_DEV`). **Don't commit it.**

---

## 7. Acceptance criteria status

| # | Criterion | Status | How to test |
|---|---|---|---|
| — | Change the Python version in `setup_script.sql` | ✅ Done | — |
| — | Packages available for that version | 🟡 Public channel ✅; account check pending | §6, step 2 |
| AC1 | Runs on the latest supported version | ⬜ | `DESCRIBE FUNCTION <app>.code_schema.validate_phone(ARRAY);` shows `runtime_version = 3.14` |
| AC2 | Results same as 3.9 (valid/invalid, carrier, line type, prepaid, activity score) | ⬜ | Same ~5 test numbers on the old 3.9 function and the new 3.14 function, back to back. Compare `data:` fields (query below). |
| AC3 | Fresh install works end to end | ⬜ | `snow app teardown` → `snow app run` → add secret + approve EAI in Snowsight → `CALL ...create_eai_objects();` (expect `SUCCESS`) → run query |
| AC4 | Existing install upgrades and still works | ⬜ | From an install with the 3.9 function: `snow app run` → query still works and runtime still 3.9 → `CALL ...create_eai_objects();` → runtime now 3.14 → query works |
| AC4 Q | Must existing customers re-run setup? | ✅ **Yes** (from code review; confirm in the AC4 test) | — |

**AC2 comparison query:**
```sql
select a.phno,
       a.data:is_valid       = b.data:is_valid       as valid_same,
       a.data:line_type      = b.data:line_type      as line_type_same,
       a.data:carrier        = b.data:carrier        as carrier_same,
       a.data:is_prepaid     = b.data:is_prepaid     as prepaid_same,
       a.data:activity_score = b.data:activity_score as score_same
from RESULTS_PY39 a join RESULTS_PY314 b on a.phno = b.phno;
```

**Edge cases to try:** an invalid number (`'123'`), a number with a leading `+` (it isn't URL-encoded, so compare with 3.9), an empty table, and a wrong API key. Each should return JSON in `data` and not crash.

**Test hygiene:** use about 5 test numbers and a test API key (every number is a real API call). Mask phone numbers in screenshots. Never paste API keys or passwords.

### Why AC4 needs a re-run
On upgrade, Snowflake re-runs `setup_script.sql`, but that only does `CREATE OR REPLACE PROCEDURE code_schema.create_eai_objects()`. The `validate_phone` function is created **inside** that procedure, so it stays on 3.9 until the customer calls it again.

Customer instruction:
> After upgrading the app, run `CALL code_schema.create_eai_objects();` once to recreate the phone-validation function using the new Python runtime.

---

## 8. Remaining work / blockers

| # | Item | Blocker / owner |
|---|---|---|
| 1 | Confirm whether `BZCWZMW-OQB00231` is the intended test account, or get a user in `WYNRKMV-CWB34849` | Ask whoever issued the login. Chandra Kewlani (`ckewlani`) set up the pipeline. |
| 2 | Run §6 checks and AC1–AC4 (§7); record results | Needs account access |
| 3 | If 3.14 isn't available, switch to `'3.13'` and re-run the build | — |
| 4 | Commit on `dev-shivani` | — |
| 5 | PR → `main` | ✅ [PR #4](https://github.com/TrestleIQ/snowflake-app-trestle/pull/4) open. Push the CI fix commit (after the lead's OK, since PR runs deploy), then update the PR description. **Don't merge yet.** |
| 6 | Release: create a new version/patch and set the release directive | **Manual.** The version-create step in `deploy.yml` is commented out. |
| 7 | Tell existing customers to re-run `create_eai_objects()` | Product / CS |
| 8 | Update Jira with test results; close the ticket | — |

### CI fix: Snowflake CLI crash (2026-10-26)
- The first CI run on PR #4 (run `40308283362`) failed in **"Install Snowflake CLI"** on `snow --version` with `Parameter.make_metavar() missing 1 required positional argument: 'ctx'`.
- Cause: `deploy.yml` pinned `snowflake-cli-labs==3.4.1` but not its dependency `click`. pip installed `click` 8.5.0, which is incompatible with the bundled `typer` 0.12.5. `click` 8.2.0 (released 10 May 2025) introduced the break. CI hadn't run since 6 Mar 2025, so this was the first run to hit it. **It isn't caused by the runtime change.**
- Fix: `pip install snowflake-cli-labs==3.4.1 "click<8.2"`. The longer-term option is to upgrade to `snowflake-cli` (3.30.0 works locally), but the `version list` JSON used by `jq` would need re-checking.

### CI caveats (`deploy.yml`)
- It runs on `pull_request`. The "Register version as released" step runs when the ref is **not** `main` (the condition looks swapped), so **opening a PR deploys and sets the default release directive** in the CI account.
- On `main`, `snow app version create` is commented out, so merging doesn't publish a version.
- It deploys as `ACCOUNTADMIN`, with the account and user hardcoded. The password is a GitHub secret.

### PR description draft (for when write access exists)
**Dependencies & Deploy Order** section:
| Type | Change | When |
|---|---|---|
| Infra | (verify) Python 3.14 + both packages available to Native App UDFs in the provider account | Before deploy |
| Next step | Create a new app version/patch and set the release directive | After merge |
| Next step | Tell existing customers to re-run `CALL code_schema.create_eai_objects();` | After release |

No dependent PRs in other repos.

---

## 9. Out of scope (noticed, not changed)

| Issue | Where | Impact |
|---|---|---|
| `end_partition()` yields an extra `(0, "")` row | `udf1.py:26-27` | Every query returns a junk `phno = 0` row |
| README query uses `trestle.public.validate_phone` | `app/README.md:45` | Customers copying it get an error; the real path is `<app>.code_schema.validate_phone` |
| No timeout on `requests.get` | `udf1.py:21` | One slow API call can hang a customer's query |
| Phone number put in the URL via f-string, not URL-encoded | `udf1.py:21` | A `+` in a number may be read as a space; use `params=` |
| Release directive set on PR runs; deploys as `ACCOUNTADMIN` | `deploy.yml` | Unintended releases; broad privileges |
| `udf.py` unused | `app/src/udf.py` | Dead code shipped in the package |

---

## 10. Git state (as of 2026-10-26)

| Branch | State |
|---|---|
| `dev-shivani` (current) | Pushed. [PR #4](https://github.com/TrestleIQ/snowflake-app-trestle/pull/4) is open into `main`. Commit `024a18b` has the runtime change. A local commit adds the CI `click` pin, `CLAUDE.md` and this doc (**not pushed yet**). **Do not merge PR #4 until Snowflake testing and sign-off.** |
| `TRES-6938-python-upgrade` | Local only. Commit `60652d1` has the same one-line change. Created before `dev-shivani`; can be deleted. |

---

## 11. Jira activity
- 2026-10-23: comment `65087` posted on TRES-6938 with findings, local validation, the AC4 answer, the blocker, test steps, and the access request or option to publish directly. **No reply yet.**

## 12. Docs
- `CLAUDE.md` was added (runtime and stack, local build, CI/deploy notes, including the `click` pin).
- `docs/context.md` is still missing (required by org standards).

## 13. References
- [Snowflake Python Runtime Support policy](https://docs.snowflake.com/en/developer-guide/python-runtime-support-policy)
- [Introduction to Python UDFs](https://docs.snowflake.com/en/developer-guide/udf/python/udf-python-introduction)
- [Python UDF handler examples](https://docs.snowflake.com/en/developer-guide/udf/python/udf-python-examples)
- [Snowflake Native Apps: setup script](https://docs.snowflake.com/en/developer-guide/native-apps/creating-setup-script)
- [Snowflake Native Apps: manifest](https://docs.snowflake.com/en/developer-guide/native-apps/creating-manifest)
