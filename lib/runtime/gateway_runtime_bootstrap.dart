import 'dart:convert';

class BridgeBootstrapEnvelope {
  const BridgeBootstrapEnvelope({
    required this.ticket,
    required this.bridgeOrigin,
  });

  final String ticket;
  final String bridgeOrigin;
}

BridgeBootstrapEnvelope? decodeBridgeBootstrapEnvelope(String rawInput) {
  final trimmed = rawInput.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return null;
  }
  try {
    final json = jsonDecode(trimmed) as Map<String, dynamic>;
    final scheme = _stringValue(json['scheme']);
    if (scheme.trim() != 'xworkmate-bridge-bootstrap') {
      return null;
    }
    final ticket = _stringValue(json['ticket']);
    final bridge = _stringValue(json['bridge']);
    if (ticket.trim().isEmpty || bridge.trim().isEmpty) {
      return null;
    }
    return BridgeBootstrapEnvelope(
      ticket: ticket.trim(),
      bridgeOrigin: bridge.trim(),
    );
  } catch (_) {
    return null;
  }
}

bool isBridgeBootstrapShortCode(String rawInput) {
  final trimmed = rawInput.trim();
  return RegExp(r'^[A-Z0-9]{6,8}$', caseSensitive: false).hasMatch(trimmed);
}

String _stringValue(Object? value) => value?.toString().trim() ?? '';
