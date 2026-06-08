import 'workspace_provision_models.dart';
import 'ssh_executor.dart';

class ServerDetector {
  const ServerDetector(this.executor);

  final WorkspaceSshExecutor executor;

  Future<ServerInfo> detect(SshConfig ssh, String workspaceDomain) async {
    final result = await executor.execute(
      ssh,
      detectionCommand(workspaceDomain),
    );
    if (!result.success) {
      throw ServerDetectionException(result.combinedOutput.trim());
    }
    return parseServerInfo(result.stdout);
  }

  static String detectionCommand(String workspaceDomain) {
    final domain = shellQuote(workspaceDomain.trim());
    return '''
if command -v lsb_release >/dev/null 2>&1; then
  echo "OS=\$(lsb_release -ds)"
else
  . /etc/os-release 2>/dev/null || true
  echo "OS=\${PRETTY_NAME:-unknown}"
fi
echo "ARCH=\$(uname -m)"
echo "SUDO=\$(sudo -n true 2>/dev/null && echo yes || echo no)"
echo "DOCKER=\$(docker --version 2>/dev/null || echo missing)"
echo "SYSTEMD=\$(systemctl --version 2>/dev/null | head -1 || echo missing)"
echo "CADDY=\$(caddy version 2>/dev/null || echo missing)"
echo "ANSIBLE=\$(ansible --version 2>/dev/null | head -1 || echo missing)"
echo "GIT=\$(git --version 2>/dev/null || echo missing)"
echo "DNS_OK=\$(getent hosts $domain 2>/dev/null | wc -l | tr -d ' ')"
echo "PORT_443_LISTENERS=\$(ss -ltn '( sport = :443 )' 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
if command -v ufw >/dev/null 2>&1; then
  UFW_STATUS="\$(ufw status 2>/dev/null || sudo -n ufw status 2>/dev/null || echo unavailable)"
  if printf '%s' "\$UFW_STATUS" | grep -qi 'Status: inactive'; then
    echo "PORT_443_OPEN=yes"
  elif printf '%s' "\$UFW_STATUS" | grep -Eqi '(^|[[:space:]])(443(/tcp)?|https)[[:space:]]+ALLOW'; then
    echo "PORT_443_OPEN=yes"
  else
    echo "PORT_443_OPEN=no"
  fi
  elif command -v firewall-cmd >/dev/null 2>&1; then
  FIREWALL_STATE="\$(firewall-cmd --state 2>/dev/null || sudo -n firewall-cmd --state 2>/dev/null || echo not-running)"
  if [ "\$FIREWALL_STATE" = "running" ]; then
    if firewall-cmd --quiet --query-service=https 2>/dev/null ||
       sudo -n firewall-cmd --quiet --query-service=https 2>/dev/null ||
       firewall-cmd --quiet --query-port=443/tcp 2>/dev/null ||
       sudo -n firewall-cmd --quiet --query-port=443/tcp 2>/dev/null; then
      echo "PORT_443_OPEN=yes"
    else
      echo "PORT_443_OPEN=no"
    fi
  else
    echo "PORT_443_OPEN=yes"
  fi
else
  echo "PORT_443_OPEN=yes"
fi
''';
  }

  static ServerInfo parseServerInfo(String output) {
    final values = <String, String>{};
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      final index = raw.indexOf('=');
      if (index <= 0) {
        continue;
      }
      values[raw.substring(0, index).trim()] = raw.substring(index + 1).trim();
    }
    return ServerInfo(
      os: values['OS'] ?? '',
      arch: values['ARCH'] ?? '',
      sudoAvailable: (values['SUDO'] ?? '').toLowerCase() == 'yes',
      dockerVersion: values['DOCKER'] ?? 'missing',
      systemdVersion: values['SYSTEMD'] ?? 'missing',
      caddyVersion: values['CADDY'] ?? 'missing',
      ansibleVersion: values['ANSIBLE'] ?? 'missing',
      gitVersion: values['GIT'] ?? 'missing',
      dnsAddressCount: int.tryParse(values['DNS_OK'] ?? '') ?? 0,
      port443ListenerCount:
          int.tryParse(values['PORT_443_LISTENERS'] ?? '') ?? 0,
      port443Open: (values['PORT_443_OPEN'] ?? '').toLowerCase() != 'no',
    );
  }
}

class ServerDetectionException implements Exception {
  const ServerDetectionException(this.message);

  final String message;

  @override
  String toString() => message.isEmpty ? 'Server detection failed' : message;
}
