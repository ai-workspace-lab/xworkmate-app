# XWorkmate Bridge Migration

## Summary

The ACP Bridge Server implementation was migrated out of `xworkmate-app` into the standalone sibling repository `xworkmate-bridge`.

This migration separates the embedded Go bridge/server from the Flutter application repository while preserving the existing helper binary contract used by the app.

## New Repository

- Repository path: `/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge`
- Go module: `xworkmate-bridge`
- Helper binary output name: `xworkmate-go-core`

## What Moved

The previous `xworkmate-app/go/go_core` implementation was migrated to `xworkmate-bridge`, including:

- ACP Bridge HTTP/WebSocket server
- ACP stdio entrypoint
- internal routing, dispatch, mounts, shared RPC helpers, gateway runtime support, memory, skills, and toolbridge packages
- Go tests for ACP routing/contracts and bridge helper behavior

## What Stayed In xworkmate-app

The following app-side concerns remain in `xworkmate-app`:

- Flutter UI and settings pages
- ACP Bridge client-side configuration and secure-storage handling
- Dart runtime launch/locator logic for the helper binary
- packaging logic that embeds the helper into the app bundle

## Build Contract

`xworkmate-app` still expects a helper named `xworkmate-go-core`.

To preserve compatibility, `xworkmate-bridge` continues to build the helper using that binary name.

## App Repository Changes

In `xworkmate-app`:

- `go/go_core` was removed
- `scripts/build-go-core.sh` now resolves and builds from sibling repo `xworkmate-bridge`
- the script supports both normal workspace layout and worktree layout
- release notes references were updated to point at the new repository

## Validation

Validated during migration:

- `cd xworkmate-bridge && go test ./...`
- `cd xworkmate-bridge && bash scripts/build-helper.sh`
- `cd xworkmate-app && bash scripts/build-go-core.sh`

## Operational Note

For local development and packaging, `xworkmate-bridge` must exist as a sibling repository next to `xworkmate-app`, unless `XWORKMATE_BRIDGE_DIR` is set explicitly.
