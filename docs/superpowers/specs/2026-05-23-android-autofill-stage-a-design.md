# Android Autofill Stage A Design

## Goal

Add the Android Autofill platform surface without weakening Lockly's zero-knowledge boundary.

Stage A is intentionally a setup and native-service foundation:

- declare a native Android `AutofillService`;
- expose a Flutter platform channel for status and system-settings launch;
- show Android Autofill posture in Settings;
- avoid native SQLite reads, plaintext caches, or background vault decryption.

## Security Boundary

The Android service must not read the vault database or platform secure storage. It must not cache usernames, passwords, master-password material, KEK, DEK, biometric DEK copies, TOTP secrets, passkey private material, attachment plaintext, or decrypted item JSON.

Until a later authenticated selection flow exists, `LocklyAutofillService` returns an empty fill response. This makes the service visible and configurable in Android settings while preventing accidental plaintext exposure from a background service.

## Platform Contract

Android integration uses the official Autofill service shape:

- manifest service with `android.permission.BIND_AUTOFILL_SERVICE`;
- `android.service.autofill.AutofillService` intent action;
- `android.autofill` metadata pointing at `res/xml/autofill_service.xml`;
- settings handoff through a Flutter `MethodChannel` named `lockly/autofill`.

The Settings page queries support/enabled state through the platform channel and opens Android system Autofill settings. It never asks for the local vault passphrase from the Autofill section.

## Later Stages

Stage B should add authenticated fill:

- parse package/domain hints from `AssistStructure`;
- require local unlock or biometric confirmation before any suggestion;
- show a Lockly credential picker when more than one encrypted item matches;
- return only the selected username/password for the active fill request;
- clear transient fill values immediately after response construction.

Stage B must remain client-only for decrypted values and should be reviewed separately before implementation.
