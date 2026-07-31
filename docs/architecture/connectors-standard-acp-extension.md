# Connectors and standard ACP Server extension

## Current product boundary

The Connectors screen is local-first:

1. Local Workspace is always ready without an account.
2. Self-hosted Workspace is the first optional connector and connects a
   workspace the user deploys and manages.
3. svc.plus Workspace is a separate optional connector for an existing
   workspace configuration.

The current release does not expose an MCP connector and does not bridge or
copy a Codex configuration. It also does not claim direct interoperability
with every ACP server.

## Future standard ACP Server connector

A future connector may accept a user-provided standard ACP Server endpoint
directly. It must be implemented as a separate connector, rather than adding
implicit fallback behavior to Self-hosted Workspace.

The connector contract should require:

- An explicit HTTPS endpoint, with loopback-only non-TLS allowed only when the
  user intentionally configures a local server.
- A user-supplied access credential stored only in secure storage.
- An explicit, user-initiated capability handshake before the connector is
  marked connected.
- A stable ACP capability mapping that declares supported session, task, and
  artifact operations rather than probing undocumented server behavior.
- Clear connection failures and a disconnect action that removes the stored
  credential and endpoint reference.

## Review and distribution boundary

Standard ACP Server support must remain an optional external-service
connection. It must not be presented as a purchase, subscription, upgrade, or
mechanism for unlocking XWorkmate features. Local Workspace remains usable
without connecting any external service.
