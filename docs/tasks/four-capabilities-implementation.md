# Four capabilities implementation and local acceptance

Date: 2026-10-03. Isolated App worktree: `xworkmate-app-four-capabilities`.
Starting App commit: `50e7cda81e74d79502b61bd858e71dfcfb9a7d7e`.
OpenCode target: v2 `35a41b5d53c71ae0337e614ec192fd5d1a5c7eb8`.
Original App checkout was not modified. This isolated candidate is submitted for review; it has not been merged or deployed.

## Implemented closure

- Chat / Work / Code are persisted product modes, independent of provider IDs. Existing desktop attachment menu and mobile configuration sheet expose them; existing composer/task/progress/file layout stays in place.
- New and unspecified execution targets default to Gateway. Every product turn preserves `xworkmateTaskArtifactContract` and includes `metadata.xworkmateProductCapability={schemaVersion:1,mode,model}`. The App connects to managed Bridge; default execution is OpenClaw Gateway, Work DSH ACP and Code pinned OpenCode v2 on server workers.
- Only the connected remote catalog's `provider=xworkmate` entries become selectable full `xworkmate/<model>` refs. A saved selection is used only if still listed; otherwise a configured listed ref or the first listed central ref is used. An empty catalog fails before task binding/prepare and does not invoke an unverified Gateway default. No provider credentials or local model presets are sent to workers.
- Actual model application is a Bridge responsibility: validate central ref, map local session key, successfully apply `sessions.patch {key,model}`, then submit. App fake transport tests validate metadata and zero submission when catalog is empty; they do not prove deployed model selection.
- Bot popup uses authenticated runtime RPC: native `cron.add` interval/isolated agentTurn with explicit central `model`, `cron.update` enabled, `cron.runs`, confirmed `cron.remove`. Empty central catalog blocks creation. Pause/history/delete preserve existing job models. All post-mutation refreshes check controller errors and surface failures.
- Notification choices are only currently configured, enabled Gateway channels with an explicit recipient. Default delivery is `none`. APNs/FCM push is not implemented.
- Existing task progress, cancellation/recovery and artifacts are reused. `.diff`/`.patch` gain text previews; `tests.log` and JSON reports remain actual scoped artifacts. There is no new structured diff/test pane and a report does not imply a passing test result.

## Cross-repo runtime boundary

The three chain maps in `docs/architecture/chain-map-{task-execution,artifact-lifecycle,session-recovery}.md` are updated in this change. Host session/run/tool-call IDs must bind the prepared task scope before workers can execute. Paths/attachments remain under the existing artifact contract; model output cannot choose run IDs or arbitrary filesystem roots. Worker export must actually produce scoped `code.diff`/`tests.log` before the App can display them.

OpenClaw npm package `2026.5.28` native cron schema was inspected, not guessed. `cron.add` does not allow arbitrary metadata; scheduling is server-side. Isolated execution uses trusted native cron identity (`cron:<jobId>` and host run session), not an App-provided path. Work/Code scheduled workers require the plugin's trusted cron hook; this App change alone does not make scheduled worker execution available.

The explicit low-level Agent transport remains only under the parent-requested migration scope; it is not the default product route. Owner: unified Gateway migration lane. Exit criterion: deployed Gateway Chat/Work/Code/Bot acceptance including cancel/artifacts/recovery. Removal is tied to that acceptance milestone; no production removal date is claimed here.

## Reproducible dependency and native packaging changes

`html: 0.15.6` is explicitly pinned because `flutter_html 3.0.0` calls `query_selector.matches`, removed in html 0.15.7. Official `PUB_HOSTED_URL=https://pub.dev flutter pub get` succeeded. The only tracked lock change is html from transitive to direct dependency, preserving its existing version/hash. Flutter 3.41.4 locally resolves SDK-pinned meta/test_api and image_picker_android; unrelated tracked lock updates were reverted. Use the repository's release toolchain for release resolution.

The iOS project lacked a Podfile despite CocoaPods-only plugins. Installed Flutter's official template was used, deployment target 15.5 kept, Pods wiring added to xcconfigs/project/workspace. Pods deployment target 15.5 avoids installed SDK 27 rejecting old pod minima. Bundle IDs, development teams, signing and entitlements were not changed. iOS Podfile.lock is necessary new build wiring. The macOS build regenerates its pre-existing incomplete Podfile.lock; that unrelated generated change is restored before delivery.

Android release no longer falls back to debug signing. Gradle and packaging script require a complete existing key.properties/upload-keystore or full CI signing environment. The script will not overwrite or remove user-owned signing files; only files created by that invocation are cleaned. A hermetic Python test proves missing signing fails before Flutter and preserves an existing keystore. `.gitignore` explicitly permits only this test under the repository's global Python ignore.

## Local validation commands and results

Installed toolchain: `/Users/shenlan/.local/devtools/flutter/bin/flutter` (Flutter 3.41.4).

| Check | Result / evidence |
| --- | --- |
| `flutter test --no-pub test/runtime/product_capability_test.dart test/runtime/central_gateway_catalog_test.dart test/runtime/gateway_bot_contract_test.dart test/runtime/desktop_thread_artifact_service_test.dart test/features/assistant/composer_input_contract_test.dart` | 26 passed; `/tmp/xworkmate-capabilities-focused-final-current.log` |
| `flutter test --no-pub test/runtime/assistant_execution_target_test.dart --plain-name 'Chat Work Code capture product semantics and central model through Gateway'` | 1 passed; three modes, valid central ref, preserved artifact contract, empty catalog produces zero submissions; `/tmp/xworkmate-central-strict-green.log` |
| `flutter test --no-pub test/runtime/assistant_execution_target_test.dart` | 77 passed (1m25), latest corrected fixtures; `/tmp/xworkmate-capabilities-gateway-fixtures-accepted.log` |
| `python3 test/scripts/android_release_signing_test.py` | 1 passed; release refusal and keystore preservation |
| `flutter analyze --no-pub` | Passed, no issues; `/tmp/xworkmate-capabilities-analyze-final-current.log` |
| `bash scripts/check-no-app-ffi.sh` | Passed, no local runtime FFI artifacts |
| `git diff --check` | Passed |
| `flutter test --no-pub --reporter expanded` | 586 passed / 23 failed (2m30s), exit 1; all failed names match the independently reproduced original baseline. No added failed name; `/tmp/xworkmate-capabilities-full-accepted.log` |

Tests were added before production implementation (RED compile/expectation failures, then GREEN). Existing goldens were executed without changing their baselines. The new desktop menu geometry test verifies the input rectangle is unchanged when opening/closing the menu; authenticated behavior uses mocked RPC, not live acceptance. Baseline golden failures below mean full visual acceptance is still open; no new Bot popup golden was recorded or existing golden refreshed.

## Builds and launch limits

Final builds must include the strict central-model check:

| Command | Output / status |
| --- | --- |
| `flutter build macos --debug --no-pub` | Built `build/macos/Build/Products/Debug/XWorkmate.app`; `/tmp/xworkmate-capabilities-macos-final-central.log` |
| `flutter build apk --debug --no-pub` | Built `build/app/outputs/flutter-apk/app-debug.apk`; `/tmp/xworkmate-capabilities-android-final-central.log` |
| `flutter build ios --debug --no-codesign --no-pub` | Built unsigned `build/ios/iphoneos/Runner.app`; `/tmp/xworkmate-capabilities-ios-final-central.log` |
| `flutter build ios --simulator --debug --no-pub` | Failed in Flutter `debug_unpack_ios` / framework copy: architecture string `arm64 x86_64` treated as one architecture although lipo lists both; Xcode exit 255. `/tmp/xworkmate-capabilities-ios-simulator-diagnostic.log` line 15206. Installed Xcode iOS SDK 27.0 and simulator runtime 26.3. No simulator App delivered; no platform architecture refactor made. |
| `flutter build appbundle --release --no-pub` without upload signing | Expected refusal: complete android/key.properties upload-key contract required; `/tmp/xworkmate-capabilities-aab-preflight.log`. No AAB produced. |

Both source and previously generated macOS/iOS Info.plist export-compliance checks passed (`ITSAppUsesNonExemptEncryption=false`); final generated macOS and iOS bundles were rechecked successfully with `bash scripts/check-apple-export-compliance.sh <bundle>` (`/tmp/xworkmate-macos-compliance-final.log`, `/tmp/xworkmate-ios-compliance-final.log`). Debug APK/macOS App are local build outputs; unsigned iOS device App is compilation evidence and needs signing for installation. No store submission, App Store/Google Play approval, real model inference, remote worker deployment, live cron execution or mobile push acceptance is claimed.

## Full-suite baseline attribution

An independent archive of the starting commit, under `/tmp/xworkmate-app-capabilities-baseline`, reproduced 23 existing failures with the same Flutter/html resolution. Runtime subset: 121 passed / 11 failed. Mobile/golden/auth subset: 63 passed / 12 failed. Exact commands and every failed name are retained in [baseline-failures.txt](four-capabilities-evidence/baseline-failures.txt). Raw local logs are `/tmp/xworkmate-capabilities-baseline.log` and `/tmp/xworkmate-capabilities-baseline-ui.log`.

These are eight artifact-download/workspace assertions, two capability/readiness assertions, one model-display fixture, two mobile home assertions, four mobile navigation assertions, two mobile account/sync assertions, one desktop golden, and three managed Bridge-auth/RPC assertions. The model-display fixture expects the old noncentral catalog/default; it already failed on the original snapshot and now also conflicts with the intentional central-only policy. Policy-specific failures must not be silently labeled baseline-equivalent.

Intermediate strict-central full run: 558 passed / 51 failed (`/tmp/xworkmate-capabilities-full-final-central.log`). This was not accepted: besides the known baseline names it included new connected fake runtime teardown, lost fake skills/catalog, old server-default expectations, and an account-test temporary-directory deletion race. The Gateway fixture now has an explicit central catalog, preserves test-defined skills, does not dial a network or emit disconnect auto-refresh events, and the former server-default test verifies explicit central metadata. The stale-skill unit now uses pure record upsert instead of unnecessary asynchronous workspace initialization. The account deletion race was not reproduced or claimed fixed.

Final full-suite failure names and attribution: [final-full-failures.txt](four-capabilities-evidence/final-full-failures.txt). Final 586 passed / 23 failed; exact failed-name set equals the original archive baseline (23/23), with no additional failed names. The account deletion race did not recur in this final run; it remains an observed intermediate fixture race, not a claimed production fix. Earlier intermediate runs exposed incomplete Gateway default fixtures and a fake-connected runtime teardown; these were corrected; final full-suite verification confirms they do not remain. They were not classified as pre-existing failures. No unrelated old baseline defect was repaired in this bounded closure.

## Final scope and remaining acceptance

Changed paths are listed in [changed-paths.txt](four-capabilities-evidence/changed-paths.txt). Scope: product modes/metadata/default Gateway, central catalog, Bot popup/native cron contract, artifact text types, relevant tests, three chain maps/README, html pin, Android signing refusal and necessary iOS Pods wiring. No unrelated macOS/Linux/Windows generated change is included.

Remaining gates: fix/accept old baseline failures in their owning tasks; deploy central catalog/provider and trusted worker/cron contracts; prove actual inference, scoped files/progress/cancel/recovery and notifications against the managed Bridge; verify mobile/desktop layouts with existing golden baselines; configure Apple/Play signing and complete privacy/export/review submission. This implementation is locally reviewable and built, not production/store accepted.


## Home-Lab deployment follow-up (2026-10-03)

CI source validation and verification passed; Linux, Windows and macOS matrix builds passed.
Android release remains correctly blocked without an upload signing contract. The iOS
unsigned CI branch exposed Bash 3.2 nounset behavior for an empty optional endpoint
array. This path is repaired without altering signing policy; a real Bash 3.2 scripted
build fixture first reproduced the failure, then passed both absent and supplied
endpoint cases. CI is being rerun for the patched candidate; full layered baseline
failures remain open. Remote runtime acceptance is recorded separately with the
Home-Lab deployment report rather than being implied by App compilation.
