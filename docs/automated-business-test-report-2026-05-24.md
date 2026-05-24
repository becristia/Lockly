# Lockly / backend-pass Automated Business Test Report

Date: 2026-05-24

## Scope

This report covers the current `Lockly` Flutter app and `backend-pass` FastAPI backend in the local workspace.

Primary goals verified:

- Local APK core flows: vault creation/unlock, password item save, password detail default secrecy, password generator, settings/security controls.
- Backend service on Windows: local FastAPI service started and verified.
- Encrypted sync: backend auth, device registration, vault metadata, encrypted item push/pull, and plaintext rejection.
- Security constraints: master password remains local; backend account password is separate; synced vault payloads are ciphertext-oriented.

## Environment

- Flutter: 3.41.6 stable, Dart 3.11.4.
- Android device: `emulator-5554`, Android 17 / API 37.
- APK package: `com.lockly.securebox`.
- APK version: `versionName=1.0.0`, `versionCode=1`.
- Backend service: `uvicorn backend.app.main:app --host 0.0.0.0 --port 8876`.
- Backend local PID during verification: `18700`.
- Backend health endpoints:
  - `GET http://127.0.0.1:8876/health` -> `{"status":"ok"}`
  - `GET http://127.0.0.1:8876/openapi.json` -> `200`

Port `8765` was already occupied by an unrelated Dart file server, so the project backend was started on `8876`.

## Automated Commands

Backend:

```powershell
python -m pytest -q
```

Result:

```text
107 passed in 126.03s (0:02:06)
```

Frontend static analysis:

```powershell
flutter analyze
```

Result:

```text
No issues found! (ran in 15.5s)
```

Frontend automated tests:

```powershell
flutter test -r compact
```

Result:

```text
480 tests passed.
```

APK build:

```powershell
flutter build apk --debug --dart-define=LOCKLY_SYNC_BASE_URL=http://10.0.2.2:8876
```

Result:

```text
Built build\app\outputs\flutter-apk\app-debug.apk
```

APK install:

```powershell
adb -s emulator-5554 install -r build\app\outputs\flutter-apk\app-debug.apk
```

Result:

```text
Success
```

## APK Business Flow Verification

Verified with ADB launch, window hierarchy dumps, and app log checks.

1. APK launch
   - `pidof com.lockly.securebox` returned a running process.
   - Current focus: `com.lockly.securebox/.MainActivity`.
   - No `FATAL EXCEPTION` or app crash was observed in filtered logcat output.

2. Vault creation and unlock
   - First attempted weak/sequential master password was rejected by policy.
   - Strong passphrase showed strength `100` and was accepted.
   - Setup page displayed zero-knowledge copy: master password is not uploaded or recoverable.
   - After vault creation, app required local master-password unlock.
   - Unlock succeeded and opened the vault home.

3. Password item save
   - Added a password entry titled `example`.
   - Home showed one local encrypted record.
   - Opened the saved detail page.
   - Detail showed the saved password as hidden by default.
   - The saved item was present without exposing plaintext in the list or default detail state.

4. Password generator
   - Generator tab opened successfully.
   - Generated a 16-character password with lowercase, uppercase, numbers, and symbols enabled.
   - The save-generated-password action became enabled after generation.

5. Settings and safety controls
   - Settings page exposed:
     - theme controls,
     - master password change,
     - biometric toggle,
     - auto-lock timeout,
     - clipboard cleanup timeout,
     - Android Autofill status/settings,
     - password health,
     - tag management,
     - Cloud sync,
     - encrypted backup export,
     - migration import,
     - clear local vault.
   - Cloud sync copy states: only encrypted vault rows sync; vault unlock stays local.

6. APK cloud account/device registration
   - Used APK Cloud register dialog with a backend account password distinct from the local vault passphrase.
   - App status became `Registered and connected`.
   - Backend access log confirmed:
     - `POST /auth/register` -> `201`
     - `POST /auth/login` -> `200`
     - `POST /devices/register` -> `201`

## Backend Live Sync Smoke

A live API smoke test was run against `http://127.0.0.1:8876` using the running Windows backend service.

Verified operations:

- User registration.
- User login.
- `GET /auth/me`.
- Device registration.
- Vault metadata initialization.
- Encrypted item push.
- Encrypted item pull.
- Plaintext field rejection.
- SQLite runtime database scan for absent backend account password and rejected plaintext secret.

Result summary:

```json
{
  "auth": "register/login/me ok",
  "vault_revision": 1,
  "pushed_revision": 1,
  "pulled_items": 1,
  "plaintext_rejection_status": 422,
  "database_plaintext_scan": "account password and rejected plaintext absent"
}
```

Backend access log evidence:

```text
POST /auth/register -> 201 Created
POST /auth/login -> 200 OK
GET /auth/me -> 200 OK
POST /devices/register -> 201 Created
POST /vault/init -> 201 Created
POST /sync/push -> 200 OK
GET /sync/pull -> 200 OK
POST /sync/push -> 422 Unprocessable Entity
```

## Security Findings

- Master password remains local in the APK flow and is required again after lock.
- Backend account password is separate from the vault master password.
- Backend stores account passwords as hashes; the live database scan did not contain the submitted backend account password.
- Sync payload accepts encrypted fields (`ciphertext`, `nonce`, `aad`) and rejects forbidden plaintext fields such as `password`.
- Rejected plaintext test value was not present in API error output or runtime database dump.
- Device response does not expose `device_public_key`.
- Android manifest hardening is covered by tests:
  - biometric and internet permissions declared,
  - Android cloud backup disabled,
  - `FLAG_SECURE` screenshot protection checked,
  - release shrinking/obfuscation rules checked.

## Notes

- No code fix was required during this verification pass.
- APK UI sync upload/download controls were verified as visible, and APK registration/device creation reached the backend. Encrypted push/pull was verified through backend live API plus the existing Flutter sync service tests.
- ADB text input through Gboard can reorder fast typed text. That affected early manual master-password attempts; the final APK flow used a stable test passphrase and hierarchy checks.

## Final Status

Current verification status: pass.

No warning-or-higher issues were found by `flutter analyze`; no failing backend or frontend tests remained.
