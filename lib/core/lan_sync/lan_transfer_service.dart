import 'dart:convert';
import 'dart:typed_data';

import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/cancellation/cancellation_token.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_client.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_crypto.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_models.dart';
import 'package:secure_box/core/lan_sync/lan_transfer_server.dart';

class LanTransferService {
  LanTransferService({
    required BackupService backupService,
    required LanTransferServer server,
    required LanTransferClient client,
    required LanTransferCrypto crypto,
  }) : _backupService = backupService,
       _server = server,
       _client = client,
       _crypto = crypto;

  final BackupService _backupService;
  final LanTransferServer _server;
  final LanTransferClient _client;
  final LanTransferCrypto _crypto;

  Future<LanTransferSession> createSendSession({
    required List<String> itemIds,
    required bool includeBlobs,
    required bool includeHistory,
    required String sourceMasterPassword,
    required String senderName,
    Duration ttl = const Duration(minutes: 5),
    String bindHost = '0.0.0.0',
    String? advertisedHost,
  }) async {
    final lanPackagePassword = _crypto.randomToken();
    final backup = await _backupService.exportLanTransferBackup(
      itemIds: itemIds,
      includeBlobs: includeBlobs,
      includeHistory: includeHistory,
      sourceMasterPassword: sourceMasterPassword,
      lanPackagePassword: lanPackagePassword,
    );
    final jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert(backup.toJson());
    final bytes = Uint8List.fromList(utf8.encode(jsonText));
    if (bytes.length > maxLanTransferEnvelopeBytes) {
      throw const FormatException('LAN transfer backup is too large to send');
    }

    return _server.start(
      packageBytes: bytes,
      selectedCount: itemIds.toSet().length,
      senderName: senderName,
      packagePassword: lanPackagePassword,
      ttl: ttl,
      bindHost: bindHost,
      advertisedHost: advertisedHost,
    );
  }

  Future<LanTransferImportResult> receiveFromPayload({
    required LanTransferQrPayload payload,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final packageBytes = await _client.download(
      payload,
      cancellationToken: cancellationToken,
    );
    cancellationToken?.throwIfCancelled();
    if (packageBytes.length > maxLanTransferEnvelopeBytes) {
      throw const FormatException('LAN transfer backup is too large to import');
    }

    final jsonText = utf8.decode(packageBytes);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw const FormatException('LAN transfer backup root must be an object');
    }
    cancellationToken?.throwIfCancelled();
    final result = await _backupService.importBackupSkippingIdentityConflicts(
      json: Map<String, Object?>.from(decoded),
      masterPassword: payload.packagePassword,
      cancellationToken: cancellationToken,
    );
    return _mapImportResult(result);
  }

  Future<void> cancelSendSession() => _server.close();

  LanTransferImportResult _mapImportResult(
    ConflictAwareBackupImportResult result,
  ) {
    return LanTransferImportResult(
      importedCount: result.importedCount,
      skippedCount: result.skippedCount,
      conflicts: result.conflicts
          .map(
            (conflict) => LanTransferConflict(
              title: conflict.title,
              website: conflict.website,
              username: conflict.username,
              reason: _mapConflictReason(conflict.reason),
            ),
          )
          .toList(growable: false),
    );
  }

  LanTransferConflictReason _mapConflictReason(
    BackupImportConflictReason reason,
  ) {
    return switch (reason) {
      BackupImportConflictReason.existingLocalEntry =>
        LanTransferConflictReason.existingLocalEntry,
      BackupImportConflictReason.duplicateIncomingEntry =>
        LanTransferConflictReason.duplicateIncomingEntry,
    };
  }
}
