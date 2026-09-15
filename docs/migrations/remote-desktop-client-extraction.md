# Remote desktop client extraction

The Flutter WebRTC desktop client and input handling code has been copied to
`ai-workspace-lab/xworkmate-remote-desktop/client/flutter/legacy` as an
extraction baseline. This copy does not deprecate or remove the implementation
here.

Until the standalone Flutter package exposes a stable signaling interface and
passes integration tests, `xworkmate-app` remains the authoritative client.
Future migration will keep the product-specific panel and state management in
this repository while consuming the standalone renderer, connection lifecycle,
and input adapter package.
