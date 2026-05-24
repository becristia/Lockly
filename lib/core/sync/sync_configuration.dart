Uri validateSyncBaseUrl(Uri baseUrl) {
  if (baseUrl.scheme == 'https') {
    return baseUrl;
  }
  if (baseUrl.scheme == 'http' && _isLocalDevelopmentHost(baseUrl.host)) {
    return baseUrl;
  }
  throw ArgumentError.value(
    baseUrl.toString(),
    'baseUrl',
    'must use https except for local development hosts',
  );
}

bool _isLocalDevelopmentHost(String host) {
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '10.0.2.2';
}
