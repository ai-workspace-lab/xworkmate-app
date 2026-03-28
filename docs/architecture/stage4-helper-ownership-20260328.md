# Stage 4 Helper Ownership (2026-03-28)

## Scope

Scan command:

```bash
rg --files lib test | rg "(helper|helpers|utils)"
```

Result: no generic `utils` directory/file; helper files are domain-scoped.

## Ownership Mapping

| File | Business closure owner | Status |
|---|---|---|
| `lib/app/app_controller_desktop_runtime_helpers.dart` | Desktop runtime base helpers (streaming text, URL parsing, observer notifications) | Kept, already reduced and scoped |
| `lib/runtime/gateway_runtime_helpers.dart` | Gateway runtime core/helper closure | Kept, domain-owned |
| `lib/runtime/direct_single_agent_app_server_client_helpers.dart` | Single-agent app-server client closure | Kept, domain-owned |
| `lib/app/app_controller_web_helpers.dart` | Web AppController helper closure | Kept, domain-owned |
| `lib/web/web_assistant_page_helpers.dart` | Web assistant page closure | Kept, domain-owned |
| `lib/features/assistant/assistant_page_composer_state_helpers.dart` | Assistant composer state closure | Kept, domain-owned |

## Stage-4 Conclusion

- No cross-domain `utils` bucket was found under `lib/` and `test/`.
- Existing helper files are already tied to explicit business closures.
- Governance decision: continue to allow `*_helpers.dart` only when the file name contains explicit domain ownership (feature/runtime/controller scope), and avoid introducing shared catch-all helpers.
