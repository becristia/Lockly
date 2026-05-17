# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build, Test, and Development Commands

```powershell
# Build debug APK
flutter build apk --debug

# Build release APK
flutter build apk --release

# Install to phone (USB device)
adb -d install -r build/app/outputs/flutter-apk/app-debug.apk

# Install to emulator
adb -e install -r build/app/outputs/flutter-apk/app-debug.apk

# Uninstall from device
adb -d uninstall com.lockly.securebox

# Run tests
flutter test

# Run specific test file
flutter test --reporter compact test/path/to/test_file.dart

# Run analyzer
flutter analyze

# Clean and rebuild
flutter clean && flutter pub get && flutter build apk --debug
```

## Architecture

**Lockly** is a Flutter Android app for local password management with end-to-end encryption.

### Directory Structure

```
lib/
├── app/           # App entry point, routing (app.dart, app_services.dart)
├── core/          # Core services
│   ├── biometric/ # Biometric authentication (local_auth wrapper)
│   ├── crypto/    # Encryption: CryptoService (AES-256-GCM), KDFService (Argon2id), SecureRandom
│   ├── security/  # AutoLockService, MasterPasswordPolicy, AppLifecycleGuard
│   ├── vault/     # VaultService, VaultSession, VaultManifest, VaultAnchor
│   ├── backup/    # BackupService (export/import encrypted backups)
│   └── clipboard/ # ClipboardService (auto-clear after timeout)
├── data/
│   ├── db/        # SQLite DAOs via sqflite
│   └── models/    # PasswordEntry, VaultManifest, VaultMeta, EncryptedVaultItem
├── features/      # UI pages
│   ├── setup/     # First-time master password creation
│   ├── unlock/    # Unlock vault with master password or biometrics
│   ├── vault_shell/ # Bottom navigation shell
│   ├── vault_list/  # Password list with search
│   ├── vault_detail/ # View password entry
│   ├── vault_edit/   # Create/edit password entry
│   ├── password_generator/ # Generate strong passwords
│   └── settings/  # Auto-lock, clipboard timeout, biometric toggle
└── shared/
    ├── theme/     # AppTheme (light/dark)
    └── widgets/   # SecureGlassCard, SecureVisualBackground, SecureGradientButton, etc.
```

### Security Model

- **KEK/DEK Architecture**: Master password → Argon2id → KEK (Key Encryption Key) → DEK (Data Encryption Key) stored in secure storage
- **Encrypted Fields**: AES-256-GCM with per-record nonce; password, notes, website fields encrypted before SQLite persistence
- **Biometric Unlock**: DEK copy encrypted with biometric key, stored in flutter_secure_storage
- **Manifest Integrity**: Vault items tracked in manifest table; tampering detected on unlock/detail/mutation/backup
- **Privacy Cover**: App lifecycle guard shows privacy cover (solid color + lock icon) when app goes to background

### Key Classes

- `AppServices` - Central service locator; handles routing, vault lifecycle, biometric, clipboard
- `VaultService` - Core vault operations: unlock, lock, CRUD items, manifest verification
- `VaultSession` - Unlocked state holder; contains decrypted DEK in memory
- `CryptoService` - AES-256-GCM encrypt/decrypt
- `BiometricService` - Wraps local_auth with custom prompt UI

### Route Flow

1. **SetupRequired** → `SetupPage` (create master password first time)
2. **Locked** → `UnlockPage` (enter master password or use biometrics)
3. **Unlocked** → `VaultShellPage` with bottom nav (vault_list, generator, settings)

### Android Config

- Package name: `com.lockly.securebox`
- Min SDK: default Flutter
- Uses `USE_BIOMETRIC` permission
- `FLAG_SECURE` on window (prevents screenshots)