import 'dart:io' show Platform;

import 'package:secure_box/core/sync/sync_api_client.dart';
import 'package:secure_box/core/sync/sync_configuration.dart';
import 'package:secure_box/core/sync/sync_credential_store.dart';
import 'package:secure_box/core/sync/sync_service.dart';
import 'package:secure_box/data/db/sync_state_dao.dart';

const locklyClientVersion = String.fromEnvironment(
  'LOCKLY_CLIENT_VERSION',
  defaultValue: '1.0.0+1',
);

SyncService? buildProductionSyncService({
  required String syncBaseUrl,
  SyncStateDao? syncState,
  SyncCredentialStore? credentials,
  SyncTransport? transport,
  SyncDeviceNameProvider? deviceName,
  String? deviceType,
  String? platform,
  String? clientVersion,
}) {
  if (syncBaseUrl.isEmpty) {
    return null;
  }

  final resolvedPlatform = platform ?? Platform.operatingSystem;
  return SyncService(
    api: SyncApiClient(
      baseUrl: validateSyncBaseUrl(Uri.parse(syncBaseUrl)),
      transport: transport ?? DartIoSyncTransport().call,
    ),
    credentials: credentials ?? SyncCredentialStore(FlutterSyncSecureStorage()),
    syncState: syncState,
    deviceName: deviceName ?? () => Platform.localHostname,
    deviceType: deviceType ?? resolvedPlatform,
    platform: resolvedPlatform,
    clientVersion: clientVersion ?? locklyClientVersion,
  );
}
