import 'dart:convert';
import 'dart:io';

import 'package:secure_box/core/sync/sync_models.dart';
import 'package:secure_box/core/sync/sync_payload_guard.dart';

typedef SyncTransport = Future<SyncHttpResponse> Function(SyncHttpRequest);

class SyncHttpRequest {
  const SyncHttpRequest({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Map<String, Object?>? body;
}

class SyncHttpResponse {
  const SyncHttpResponse(this.statusCode, this.body) : rawBody = null;

  const SyncHttpResponse.raw(this.statusCode, this.rawBody) : body = const {};

  final int statusCode;
  final Map<String, Object?> body;
  final String? rawBody;
}

class DartIoSyncTransport {
  DartIoSyncTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<SyncHttpResponse> call(SyncHttpRequest request) async {
    final httpRequest = await _client.openUrl(request.method, request.url);
    for (final entry in request.headers.entries) {
      httpRequest.headers.set(entry.key, entry.value);
    }
    final body = request.body;
    if (body != null) {
      httpRequest.write(jsonEncode(body));
    }

    final response = await httpRequest.close();
    final text = await utf8.decodeStream(response);
    if (text.isEmpty) {
      return SyncHttpResponse(response.statusCode, const {});
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return SyncHttpResponse.raw(response.statusCode, text);
      }
      return SyncHttpResponse(
        response.statusCode,
        Map<String, Object?>.from(decoded),
      );
    } on FormatException {
      return SyncHttpResponse.raw(response.statusCode, text);
    }
  }
}

class SyncApiException implements Exception {
  const SyncApiException({
    required this.statusCode,
    required this.code,
    this.message,
  });

  final int statusCode;
  final String code;
  final String? message;

  @override
  String toString() {
    final message = this.message;
    if (message == null || message.isEmpty) {
      return 'SyncApiException($statusCode, $code)';
    }
    return 'SyncApiException($statusCode, $code): $message';
  }
}

class SyncApiClient {
  SyncApiClient({required Uri baseUrl, required SyncTransport transport})
    : _baseUrl = baseUrl,
      _transport = transport;

  final Uri _baseUrl;
  final SyncTransport _transport;

  Future<SyncAccount> register({
    required String email,
    required String password,
  }) async {
    final json = await _request(
      'POST',
      '/auth/register',
      body: {'email': email, 'password': password},
    );
    return SyncAccount.fromJson(json);
  }

  Future<SyncAuthTokens> login({
    required String email,
    required String password,
  }) async {
    final json = await _request(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    return SyncAuthTokens.fromJson(json);
  }

  Future<SyncAuthTokens> refresh({required String refreshToken}) async {
    final json = await _request(
      'POST',
      '/auth/refresh',
      body: {'refresh_token': refreshToken},
    );
    return SyncAuthTokens.fromJson(json);
  }

  Future<void> logout({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _request(
      'POST',
      '/auth/logout',
      accessToken: accessToken,
      body: {'refresh_token': refreshToken},
    );
  }

  Future<SyncDevice> registerDevice({
    required String accessToken,
    required String deviceName,
    String? deviceType,
    String? platform,
    String? clientVersion,
  }) async {
    final body = <String, Object?>{'device_name': deviceName};
    if (deviceType != null) {
      body['device_type'] = deviceType;
    }
    if (platform != null) {
      body['platform'] = platform;
    }
    if (clientVersion != null) {
      body['client_version'] = clientVersion;
    }

    final json = await _request(
      'POST',
      '/devices/register',
      accessToken: accessToken,
      body: body,
    );
    return SyncDevice.fromJson(_unwrapObject(json, 'device'));
  }

  Future<SyncDevice> renameDevice({
    required String accessToken,
    required String deviceId,
    required String deviceName,
  }) async {
    final json = await _request(
      'PATCH',
      '/devices/$deviceId',
      accessToken: accessToken,
      body: {'device_name': deviceName},
    );
    return SyncDevice.fromJson(_unwrapObject(json, 'device'));
  }

  Future<List<SyncDevice>> listDevices({required String accessToken}) async {
    final json = await _request('GET', '/devices', accessToken: accessToken);
    _assertResponseFields(json, {'items'}, 'devices response');
    final devices = json['items'];
    if (devices is! List) {
      throw const FormatException('Invalid "items": expected a list');
    }

    return devices.map((device) {
      if (device is! Map) {
        throw const FormatException('Invalid "items": expected objects');
      }
      return SyncDevice.fromJson(Map<String, Object?>.from(device));
    }).toList();
  }

  Future<void> revokeDevice({
    required String accessToken,
    required String deviceId,
  }) async {
    await _request('DELETE', '/devices/$deviceId', accessToken: accessToken);
  }

  Future<SyncVaultMetaPayload> initVault({
    required String accessToken,
    required SyncVaultMetaPayload meta,
  }) async {
    final body = meta.toJson(includeRevision: false);
    assertNoForbiddenSyncFields(body);
    final json = await _request(
      'POST',
      '/vault/init',
      accessToken: accessToken,
      body: body,
    );
    return SyncVaultMetaPayload.fromJson(_unwrapObject(json, 'vault'));
  }

  Future<SyncVaultMetaPayload> getVaultMeta({
    required String accessToken,
    required String deviceId,
  }) async {
    final json = await _request(
      'GET',
      '/vault/meta',
      accessToken: accessToken,
      query: {'device_id': deviceId},
    );
    return SyncVaultMetaPayload.fromJson(_unwrapObject(json, 'vault'));
  }

  Future<SyncVaultMetaPayload> updateVaultMeta({
    required String accessToken,
    required String deviceId,
    required SyncVaultMetaPayload meta,
  }) async {
    final body = meta.toJson();
    assertNoForbiddenSyncFields(body);
    final json = await _request(
      'PUT',
      '/vault/meta',
      accessToken: accessToken,
      query: {'device_id': deviceId},
      body: body,
    );
    return SyncVaultMetaPayload.fromJson(_unwrapObject(json, 'vault'));
  }

  Future<SyncPushResponse> push({
    required String accessToken,
    required String deviceId,
    required List<SyncItem> items,
  }) {
    return pushRaw(
      accessToken: accessToken,
      deviceId: deviceId,
      items: items.map((item) => item.toJson()).toList(),
    );
  }

  Future<SyncPushResponse> pushRaw({
    required String accessToken,
    required String deviceId,
    required List<Map<String, Object?>> items,
  }) async {
    assertNoForbiddenSyncFields(items);
    assertSafeSyncItemsAad(items);
    try {
      SyncItem.assertSafeRawItems(items);
    } on FormatException catch (error) {
      throw StateError('Unsafe sync item: ${error.message}');
    }
    final response = await _send(
      'POST',
      '/sync/push',
      accessToken: accessToken,
      body: {'device_id': deviceId, 'items': items},
    );
    if (response.rawBody != null) {
      throw _exceptionFrom(response);
    }
    if (response.statusCode == 409) {
      return SyncPushResponse.fromJson(response.body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFrom(response);
    }
    return SyncPushResponse.fromJson(response.body);
  }

  Future<SyncPullResponse> pull({
    required String accessToken,
    required String since,
    required String deviceId,
  }) async {
    final json = await _request(
      'GET',
      '/sync/pull',
      accessToken: accessToken,
      query: {'since': since, 'device_id': deviceId},
    );
    return SyncPullResponse.fromJson(json);
  }

  Future<SyncBlobPushResponse> pushBlobs({
    required String accessToken,
    required String deviceId,
    required List<SyncBlob> blobs,
  }) {
    return pushRawBlobs(
      accessToken: accessToken,
      deviceId: deviceId,
      blobs: blobs.map((blob) => blob.toPushJson()).toList(),
    );
  }

  Future<SyncBlobPushResponse> pushRawBlobs({
    required String accessToken,
    required String deviceId,
    required List<Map<String, Object?>> blobs,
  }) async {
    assertNoForbiddenSyncFields(blobs);
    try {
      SyncBlob.assertSafeRawBlobs(blobs);
    } on FormatException catch (error) {
      throw StateError('Unsafe sync blob: ${error.message}');
    }
    final response = await _send(
      'POST',
      '/blobs/push',
      accessToken: accessToken,
      body: {'device_id': deviceId, 'blobs': blobs},
    );
    if (response.rawBody != null) {
      throw _exceptionFrom(response);
    }
    if (response.statusCode == 409) {
      return SyncBlobPushResponse.fromJson(response.body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFrom(response);
    }
    return SyncBlobPushResponse.fromJson(response.body);
  }

  Future<SyncVaultPushResponse> pushVault({
    required String accessToken,
    required String deviceId,
    required List<SyncItem> items,
    required List<SyncBlob> blobs,
  }) async {
    final rawItems = items.map((item) => item.toJson()).toList();
    final rawBlobs = blobs.map((blob) => blob.toPushJson()).toList();
    assertNoForbiddenSyncFields(rawItems);
    assertNoForbiddenSyncFields(rawBlobs);
    assertSafeSyncItemsAad(rawItems);
    try {
      SyncItem.assertSafeRawItems(rawItems);
      SyncBlob.assertSafeRawBlobs(rawBlobs);
    } on FormatException catch (error) {
      throw StateError('Unsafe sync vault push: ${error.message}');
    }
    final response = await _send(
      'POST',
      '/sync/push-vault',
      accessToken: accessToken,
      body: {'device_id': deviceId, 'items': rawItems, 'blobs': rawBlobs},
    );
    if (response.rawBody != null) {
      throw _exceptionFrom(response);
    }
    if (response.statusCode == 409) {
      return SyncVaultPushResponse.fromJson(response.body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFrom(response);
    }
    return SyncVaultPushResponse.fromJson(response.body);
  }

  Future<SyncBlobPullResponse> pullBlobs({
    required String accessToken,
    required String since,
    required String deviceId,
  }) async {
    final json = await _request(
      'GET',
      '/blobs/pull',
      accessToken: accessToken,
      query: {'since': since, 'device_id': deviceId},
    );
    return SyncBlobPullResponse.fromJson(json);
  }

  Future<EmergencyContact> createEmergencyContact({
    required String accessToken,
    required EmergencyContactCreateRequest request,
  }) async {
    final json = await _request(
      'POST',
      '/emergency/contacts',
      accessToken: accessToken,
      body: request.toJson(),
    );
    return EmergencyContact.fromJson(json);
  }

  Future<List<EmergencyContact>> listEmergencyContacts({
    required String accessToken,
  }) async {
    final json = await _request(
      'GET',
      '/emergency/contacts',
      accessToken: accessToken,
    );
    return EmergencyContactListResponse.fromJson(json).items;
  }

  Future<EmergencyContact> revokeEmergencyContact({
    required String accessToken,
    required String contactId,
  }) async {
    final safeContactId = _emergencyPathSegment(contactId, 'contact_id');
    final json = await _request(
      'DELETE',
      '/emergency/contacts/$safeContactId',
      accessToken: accessToken,
    );
    return EmergencyContact.fromJson(json);
  }

  Future<EmergencyGrant> createEmergencyGrant({
    required String accessToken,
    required EmergencyGrantCreateRequest request,
  }) async {
    final json = await _request(
      'POST',
      '/emergency/grants',
      accessToken: accessToken,
      body: request.toJson(),
    );
    return EmergencyGrant.fromJson(json);
  }

  Future<List<EmergencyGrant>> listEmergencyGrants({
    required String accessToken,
  }) async {
    final json = await _request(
      'GET',
      '/emergency/grants',
      accessToken: accessToken,
    );
    return EmergencyGrantListResponse.fromJson(json).items;
  }

  Future<EmergencyGrant> acceptEmergencyGrant({
    required String accessToken,
    required String grantId,
    required String recipientKeyFingerprint,
  }) async {
    final safeGrantId = _emergencyPathSegment(grantId, 'grant_id');
    final json = await _request(
      'POST',
      '/emergency/grants/$safeGrantId/accept',
      accessToken: accessToken,
      body: EmergencyGrantAcceptRequest(
        recipientKeyFingerprint: recipientKeyFingerprint,
      ).toJson(),
    );
    return EmergencyGrant.fromJson(json);
  }

  Future<EmergencyGrant> requestEmergencyGrantAccess({
    required String accessToken,
    required String grantId,
    String? requestMessageCiphertext,
    String? requestMessageAad,
  }) async {
    final safeGrantId = _emergencyPathSegment(grantId, 'grant_id');
    final json = await _request(
      'POST',
      '/emergency/grants/$safeGrantId/request-access',
      accessToken: accessToken,
      body: EmergencyGrantRequestAccessRequest(
        requestMessageCiphertext: requestMessageCiphertext,
        requestMessageAad: requestMessageAad,
      ).toJson(),
    );
    return EmergencyGrant.fromJson(json);
  }

  Future<EmergencyGrant> cancelEmergencyGrant({
    required String accessToken,
    required String grantId,
  }) async {
    final safeGrantId = _emergencyPathSegment(grantId, 'grant_id');
    final json = await _request(
      'POST',
      '/emergency/grants/$safeGrantId/cancel',
      accessToken: accessToken,
    );
    return EmergencyGrant.fromJson(json);
  }

  Future<EmergencyGrant> revokeEmergencyGrant({
    required String accessToken,
    required String grantId,
  }) async {
    final safeGrantId = _emergencyPathSegment(grantId, 'grant_id');
    final json = await _request(
      'DELETE',
      '/emergency/grants/$safeGrantId',
      accessToken: accessToken,
    );
    return EmergencyGrant.fromJson(json);
  }

  Future<EmergencyAccessPackage> downloadEmergencyAccessPackage({
    required String accessToken,
    required String grantId,
  }) async {
    final safeGrantId = _emergencyPathSegment(grantId, 'grant_id');
    final json = await _request(
      'GET',
      '/emergency/grants/$safeGrantId/package',
      accessToken: accessToken,
    );
    return EmergencyAccessPackage.fromJson(json);
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    String? accessToken,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final response = await _send(
      method,
      path,
      accessToken: accessToken,
      query: query,
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFrom(response);
    }
    return response.body;
  }

  Future<SyncHttpResponse> _send(
    String method,
    String path, {
    String? accessToken,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    if (accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    return _transport(
      SyncHttpRequest(
        method: method,
        url: _resolve(path, query),
        headers: headers,
        body: body,
      ),
    );
  }

  Uri _resolve(String path, Map<String, String>? query) {
    final basePath = _baseUrl.path.endsWith('/')
        ? _baseUrl.path.substring(0, _baseUrl.path.length - 1)
        : _baseUrl.path;
    final endpointPath = path.startsWith('/') ? path : '/$path';
    return _baseUrl.replace(
      path: '$basePath$endpointPath',
      queryParameters: query,
    );
  }
}

String _emergencyPathSegment(String value, String label) {
  try {
    assertSafeEmergencyPathSegment(value, label);
  } on FormatException catch (error) {
    throw StateError('Unsafe emergency path segment: ${error.message}');
  }
  return Uri.encodeComponent(value);
}

Map<String, Object?> _unwrapObject(Map<String, Object?> json, String field) {
  if (json.containsKey(field)) {
    final unsupported = json.keys.toSet().difference({field});
    if (unsupported.isNotEmpty) {
      throw FormatException('Invalid "$field" response: unsupported field');
    }
  }
  final wrapped = json[field];
  if (wrapped is Map) {
    return Map<String, Object?>.from(wrapped);
  }
  if (json.containsKey(field)) {
    throw FormatException('Invalid "$field" response: expected object');
  }
  return json;
}

void _assertResponseFields(
  Map<String, Object?> json,
  Set<String> allowedFields,
  String label,
) {
  final forbidden = findForbiddenSyncFields(json);
  if (forbidden.isNotEmpty) {
    throw FormatException('Invalid "$label": forbidden field');
  }
  final unsupported = json.keys.toSet().difference(allowedFields);
  if (unsupported.isNotEmpty) {
    throw FormatException('Invalid "$label": unsupported field');
  }
}

SyncApiException _exceptionFrom(SyncHttpResponse response) {
  if (response.rawBody != null) {
    return SyncApiException(
      statusCode: response.statusCode,
      code: 'HTTP_${response.statusCode}',
    );
  }
  final error = response.body['error'];
  if (error is Map) {
    final code = error['code'];
    final message = error['message'];
    return SyncApiException(
      statusCode: response.statusCode,
      code: code is String ? code : 'HTTP_${response.statusCode}',
      message: message is String ? message : null,
    );
  }

  return SyncApiException(
    statusCode: response.statusCode,
    code: 'HTTP_${response.statusCode}',
  );
}
