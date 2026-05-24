import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/sync/sync_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fake emergency access facade supports contact and grant flows',
    () async {
      final services = AppServices.fake(
        hasVault: true,
        unlocked: true,
        emergencyContacts: [_emergencyContact()],
        emergencyGrants: [_emergencyGrant()],
        emergencyAccessPackage: _emergencyAccessPackage(),
      );
      addTearDown(services.dispose);

      expect((await services.listEmergencyContacts()).single.id, 'contact-1');

      final createdContact = await services.createEmergencyContact(
        request: const EmergencyContactCreateRequest(
          recipientEmail: 'backup@example.test',
          recipientPublicKey: 'recipient-public-key-2',
          recipientKeyFingerprint: 'fingerprint-2',
          recipientLabel: 'Backup',
        ),
      );
      final revokedContact = await services.revokeEmergencyContact(
        createdContact.id,
      );

      expect(createdContact.recipientEmail, 'backup@example.test');
      expect(revokedContact.status, 'revoked');
      expect(await services.listEmergencyContacts(), hasLength(2));

      final createdGrant = await services.createEmergencyGrant(
        request: const EmergencyGrantCreateRequest(
          contactId: 'contact-1',
          waitingPeriodHours: 24,
          encryptedRecoveryPackage: _safeEmergencyPackageEnvelope,
          packageAad: _safeEmergencyPackageAad,
          packageFingerprint: 'package-fingerprint-1',
        ),
      );
      final accepted = await services.acceptEmergencyGrant(
        grantId: createdGrant.id,
        recipientKeyFingerprint: 'fingerprint-1',
      );
      final requested = await services.requestEmergencyGrantAccess(
        grantId: createdGrant.id,
        requestMessageCiphertext: 'request-ciphertext',
        requestMessageAad: _safeEmergencyRequestMessageAad,
      );
      final cancelled = await services.cancelEmergencyGrant(createdGrant.id);
      final revokedGrant = await services.revokeEmergencyGrant(createdGrant.id);
      final package = await services.downloadEmergencyAccessPackage(
        createdGrant.id,
      );

      expect(await services.listEmergencyGrants(), hasLength(2));
      expect(createdGrant.status, 'pending_acceptance');
      expect(createdGrant.packageAad, _safeEmergencyPackageAad);
      expect(accepted.status, 'active');
      expect(requested.status, 'access_requested');
      expect(cancelled.status, 'cancelled');
      expect(revokedGrant.status, 'revoked');
      expect(package.encryptedRecoveryPackage, _safeEmergencyPackageEnvelope);
      expect(
        [
          accepted.status,
          requested.status,
          cancelled.status,
          revokedGrant.status,
          package.encryptedRecoveryPackage,
        ].join(' '),
        isNot(contains('plaintext-recovery-secret')),
      );
    },
  );
}

const String _safeEmergencyPackageEnvelope =
    '{"ciphertext":"emergency-ciphertext","nonce":"emergency-nonce","mac":"emergency-mac"}';

const String _safeEmergencyPackageAad =
    '{"schema":"lockly-emergency-package-v1","mac":"emergency-mac","grant_id":"grant-1","recipient_key_fingerprint":"fingerprint-1"}';

const String _safeEmergencyRequestMessageAad =
    '{"schema":"lockly-emergency-request-v1","mac":"message-mac"}';

EmergencyContact _emergencyContact() {
  return const EmergencyContact(
    id: 'contact-1',
    ownerUserId: 'owner-1',
    recipientUserId: 'recipient-1',
    recipientEmail: 'friend@example.test',
    recipientPublicKey: 'recipient-public-key',
    recipientKeyFingerprint: 'fingerprint-1',
    recipientLabel: 'Friend',
    status: 'active',
    createdAt: '2026-05-24T00:00:00Z',
    updatedAt: '2026-05-24T00:30:00Z',
  );
}

EmergencyGrant _emergencyGrant() {
  return const EmergencyGrant(
    id: 'grant-1',
    ownerUserId: 'owner-1',
    recipientUserId: 'recipient-1',
    contactId: 'contact-1',
    vaultId: 'vault-1',
    status: 'pending_acceptance',
    waitingPeriodHours: 24,
    packageAad: _safeEmergencyPackageAad,
    packageFingerprint: 'package-fingerprint-1',
    recipientKeyFingerprint: 'fingerprint-1',
    createdAt: '2026-05-24T00:00:00Z',
    updatedAt: '2026-05-24T00:30:00Z',
  );
}

EmergencyAccessPackage _emergencyAccessPackage() {
  return const EmergencyAccessPackage(
    grantId: 'grant-1',
    ownerUserId: 'owner-1',
    recipientUserId: 'recipient-1',
    contactId: 'contact-1',
    status: 'downloaded',
    encryptedRecoveryPackage: _safeEmergencyPackageEnvelope,
    packageAad: _safeEmergencyPackageAad,
    packageFingerprint: 'package-fingerprint-1',
    recipientKeyFingerprint: 'fingerprint-1',
    downloadedAt: '2026-05-24T01:00:00Z',
  );
}
