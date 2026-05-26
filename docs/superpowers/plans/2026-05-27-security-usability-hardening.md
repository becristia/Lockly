# Security Usability Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the repository security and usability findings from the 2026-05-27 review, including the previous LAN sync warning set.

**Architecture:** Keep the zero-knowledge boundary: the backend validates structure and session/device authority, while the frontend performs encryption, re-encryption, and master-password verification locally. Backend hardening is limited to `backend-pass`; frontend hardening is limited to `Lockly`.

**Tech Stack:** Flutter/Dart, FastAPI/Pydantic/SQLAlchemy/Alembic, pytest, flutter_test.

---

### Task 1: Backend Admin And Auth Hardening

**Files:**
- Modify: `backend-pass/backend/app/security/tokens.py`
- Modify: `backend-pass/backend/app/security/admin_auth.py`
- Modify: `backend-pass/backend/app/security/dependencies.py`
- Modify: `backend-pass/backend/app/security/auth_sessions.py`
- Modify: `backend-pass/backend/app/admin/routes.py`
- Modify: `backend-pass/backend/app/admin/templates/*.html`
- Modify: `backend-pass/tests/test_admin.py`
- Modify: `backend-pass/tests/test_auth_devices_vault_sync.py`

- [x] Add failing tests for admin CSRF rejection, admin cookie secret isolation, production secure cookie behavior, and revoked access-token rejection.
- [x] Implement admin JWT signing with `ADMIN_SESSION_SECRET`.
- [x] Add admin CSRF token creation/verification and hidden form fields for every admin POST.
- [x] Bind access tokens to auth sessions through `sid` and reject revoked/expired sessions in `current_user`.
- [x] Run targeted pytest for admin/auth tests.

### Task 2: Backend Protocol, Deployment, And Emergency Hardening

**Files:**
- Modify: `backend-pass/backend/app/config.py`
- Modify: `backend-pass/backend/app/main.py`
- Modify: `backend-pass/backend/app/db.py`
- Modify: `backend-pass/backend/app/vaults/routes.py`
- Modify: `backend-pass/backend/app/sync/routes.py`
- Modify: `backend-pass/backend/app/blobs/routes.py`
- Modify: `backend-pass/backend/app/emergency/routes.py`
- Modify: `backend-pass/backend/docker-compose.yml`
- Modify: `backend-pass/backend/migrations/README.md`
- Modify: `backend-pass/tests/test_*`

- [x] Add failing tests for ciphertext terms being accepted, explicit plaintext assignment still rejected, emergency package expiry, sync/blob pull pagination caps, and production startup migration behavior.
- [x] Relax opaque ciphertext validation to structural checks plus explicit plaintext-assignment rejection.
- [x] Add emergency package expiry enforcement.
- [x] Add pull limits/cursor caps.
- [x] Remove production `create_all()` startup behavior and keep test/local initialization explicit.
- [x] Harden compose defaults for database exposure and password configuration.

### Task 3: Frontend Sensitive Input And Operations

**Files:**
- Modify: `Lockly/lib/shared/widgets/activity_text_form_field.dart`
- Modify: `Lockly/lib/features/settings/settings_page.dart`
- Modify: `Lockly/lib/features/vault_detail/vault_detail_page.dart`
- Modify: `Lockly/lib/app/app_services.dart`
- Modify: `Lockly/lib/core/vault/vault_service.dart`
- Modify: `Lockly/lib/shared/i18n/app_strings*.dart`
- Modify: `Lockly/test/features/*`
- Modify: `Lockly/test/core/*`

- [x] Add failing widget/unit tests for password fields disabling suggestions, export/clear requiring master password, backup dialog not rendering full JSON, attachment size limits, and CSV partial failure reporting.
- [x] Implement secure password field defaults and update direct sensitive `TextFormField`s.
- [x] Require master-password reauthentication for full export, item export, and local vault clearing.
- [x] Stop rendering full backup JSON by default; require explicit copy confirmation and immediate clear path.
- [x] Add attachment size limits and text preview limits.
- [x] Make CSV import all-or-nothing or return precise partial failure information.

### Task 4: LAN Sync Warning Closure

**Files:**
- Modify: `Lockly/lib/features/lan_sync/lan_send_page.dart`
- Modify: `Lockly/lib/features/lan_sync/lan_receive_page.dart`
- Modify: `Lockly/lib/shared/i18n/app_strings*.dart`
- Modify: `Lockly/test/features/lan_sync_page_test.dart`

- [x] Add failing widget tests for the six known warning cases: send creation error mapping, receive malformed mapping, QR decode mapping, empty source password feedback, cancelled password prompt clearing accepted payload summary, and cancel-session waiting state.
- [x] Implement specific error messages and UI cleanup states.
- [x] Run LAN page tests and LAN transfer service tests.

### Task 5: Documentation And Release Hygiene

**Files:**
- Modify: `Lockly/docs/security-check.md`
- Modify: `Lockly/docs/manual-lan-sync-test-plan-2026-05-25.md`
- Modify: `Lockly/.gitignore`
- Modify: `Lockly/lib/features/totp/totp_page.dart`
- Modify: `Lockly/lib/shared/i18n/app_strings*.dart`

- [x] Rewrite stale cloud-sync security text for LAN sync.
- [x] Add Android signing secret patterns to `.gitignore`.
- [x] Localize remaining hard-coded TOTP copy text.
- [x] Run `flutter analyze`, relevant Flutter tests, and `python -m pytest -q`.

---

### Completion Notes

- 2026-05-27: Frontend and backend subagent reviews completed with no remaining Critical, Important, or Minor findings after fixes.
- 2026-05-27: Final verification commands completed:
  - `flutter analyze`
  - `flutter test`
  - `python -m pytest -q`
