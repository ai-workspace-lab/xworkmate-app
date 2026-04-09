# Settings Integration Configuration Model

This document records the logical model behind the Settings -> Integrations page.

The page is organized into three layers:

- User login state
- Base connection configuration
- Advanced custom mode

The base connection layer is the default configuration surface. It represents the connection identity that can come from either `svc.plus` or a self-hosted service. Advanced custom mode does not replace the base layer; it overrides selected defaults on top of it.

```mermaid
flowchart TD
  A[Settings Integrations Page] --> B[User Login State]
  A --> C[Base Connection Configuration]
  A --> D[Advanced Custom Mode]

  B --> B1[Signed out]
  B --> B2[Signed in]
  B --> B3[MFA pending]
  B --> B4[Signing in]

  C --> C1[Account / Email]
  C --> C2[Password]
  C --> C3[Service URL]
  C --> C4[User]
  C --> C5[Sync]
  C --> C6[Default connection source]
  C6 --> C7[svc.plus provided]
  C6 --> C8[Self-hosted]

  D --> D1[Override OpenClaw Gateway]
  D --> D2[Override Vault Server]
  D --> D3[Override LLM Endpoint]
  D --> D4[Override External ACP Server endpoint]
  D --> D5[Override SKILLS directories]

  B2 --> C
  C --> D
  D --> E[Final effective configuration]
```

## Notes

- User login state describes authentication only.
- Base connection configuration describes the default connection path and identity.
- Advanced custom mode is a layered override mechanism.
- The effective runtime configuration is computed from the base layer plus any advanced overrides.

