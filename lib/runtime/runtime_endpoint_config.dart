/// Build-time endpoint configuration for managed deployments.
///
/// Deployment pipelines provide these values with `--dart-define`. An empty
/// value deliberately leaves the connector unconfigured until the user enters
/// an account URL or the authenticated Accounts profile supplies a Bridge URL.
const String kConfiguredAccountBaseUrl = String.fromEnvironment(
  'XWORKMATE_ACCOUNT_BASE_URL',
  defaultValue: '',
);

const String kConfiguredManagedBridgeServerUrl = String.fromEnvironment(
  'XWORKMATE_MANAGED_BRIDGE_URL',
  defaultValue: '',
);

String? configuredManagedBridgeServerUrl({String remote = ''}) {
  final candidates = <String>[
    remote.trim(),
    kConfiguredManagedBridgeServerUrl.trim(),
  ];
  for (final candidate in candidates) {
    if (candidate.isEmpty) {
      continue;
    }
    final uri = Uri.tryParse(candidate);
    if (uri != null && uri.hasScheme && uri.host.trim().isNotEmpty) {
      // Rebuild the authority/path explicitly so a profile URL cannot carry
      // query or fragment state into connector requests (Uri.replace keeps
      // an empty `?#` marker for some parsed inputs).
      return Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: uri.host,
        port: uri.port,
        path: uri.path,
      ).toString();
    }
  }
  return null;
}
