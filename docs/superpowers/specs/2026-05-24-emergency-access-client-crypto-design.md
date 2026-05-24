# Emergency Access Client Crypto Design

## Goal

Build the client-side crypto foundation for Emergency Access without weakening Lockly's zero-knowledge boundary. The backend coordinates contacts, grants, waiting periods, and encrypted package release only; it must never receive the local master password, KEK, raw DEK, recipient private key, package plaintext, decrypted vault entries, TOTP secrets, attachment plaintext, or passkey private material.

## Current Backend Boundary

The backend accepts `recipient_public_key`, `recipient_key_fingerprint`, grant metadata, and an `encrypted_recovery_package` JSON string. Grant metadata and list responses never return the package body. `GET /emergency/grants/{grant_id}/package` is the only package-returning endpoint and it consumes the package by moving the grant to `downloaded`; later racing requests return `409 INVALID_STATE`.

The backend package body limit is 64 KB and recipients cannot read the owner's sync rows. Therefore this phase must not claim complete cloud-vault restoration. It can create, upload, download, and decrypt a compact client recovery package; full vault recovery needs a later backend design for encrypted vault export/release.

## Crypto Shape

Use existing dependency `cryptography`:

- Generate recipient keys with X25519.
- Export public and private keys as versioned safe-token strings with hex payloads.
- Compute recipient key fingerprint as SHA-256 over the public key bytes, encoded as a safe-token string.
- Encrypt package plaintext with an ephemeral X25519 sender key, HKDF-SHA256, and AES-256-GCM.
- Put the ephemeral sender public key in the envelope `ciphertext` value as a fixed 32-byte prefix followed by AES-GCM ciphertext, all hex encoded.
- Use the exact canonical `package_aad` JSON string as AEAD AAD. It contains `schema`, `mac`, optional `grant_id`, and `recipient_key_fingerprint`; if the caller omits the recipient fingerprint, the crypto service computes it from the recipient public key and still writes it into AAD.
- Keep backend envelope fields exact: `ciphertext`, `nonce`, `mac`.

All tokens sent to the backend must pass the existing Emergency DTO guards. Hex is preferred over base64 to avoid accidental forbidden marker matches in random data.

## Package Semantics

This stage exposes a generic encrypted package service. The package plaintext is supplied by a higher-level caller and returned only after local decryption. The service must not invent weak placeholder encryption, fixed keys, hashes-as-encryption, or server-side crypto.

The first UI slice should describe this as "emergency recovery package" or "recovery material", not "complete vault restore". When full recovery is implemented, the package must either carry a compact key-recovery material with a separate authorized encrypted-vault release path, or the backend must support storing/releasing a bounded encrypted vault export.

## API Surface

Create `lib/core/emergency/emergency_crypto_service.dart` with:

- `EmergencyKeyPairBundle`: public key token, private key token, fingerprint.
- `EmergencyEncryptedPackage`: encrypted recovery package string, package AAD string, package fingerprint.
- `EmergencyCryptoService.generateKeyPair()`.
- `EmergencyCryptoService.fingerprintForPublicKey(String publicKeyToken)`.
- `EmergencyCryptoService.encryptPackage(...)`.
- `EmergencyCryptoService.decryptPackage(...)`.

`decryptPackage` must verify:

- The private key token is versioned and local-only.
- The recipient fingerprint in AAD matches the private key public fingerprint.
- The package fingerprint matches the envelope and AAD.
- AEAD authentication succeeds before returning plaintext.

## Tests

Add `test/core/emergency/emergency_crypto_service_test.dart` covering:

- Key generation returns safe-token public/private/fingerprint strings.
- Encrypt/decrypt roundtrip with non-sensitive test plaintext.
- Envelope and AAD pass existing `EmergencyGrantCreateRequest` DTO validation.
- Tampered ciphertext, MAC, AAD, or package fingerprint fails closed.
- Wrong recipient key fails closed.
- Envelope JSON does not contain package plaintext or forbidden field names.

Run:

- `flutter test -r compact test\core\emergency\emergency_crypto_service_test.dart test\core\sync\sync_models_test.dart`
- `flutter analyze`
- If feasible, `flutter test -r compact`
