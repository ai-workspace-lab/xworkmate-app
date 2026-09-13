# Google Play release checklist

XWorkmate is published as an Android application with the immutable package
name `plus.svc.xworkmate`. The value is declared in
`android/app/build.gradle.kts` and must not change after the Play Console app is
created.

## Build outputs

The Android CI lane creates:

- `dist/android/xworkmate-android.aab` — upload this Android App Bundle to
  Google Play (internal testing first).
- `dist/android/xworkmate-android-arm64.apk` — device smoke-test artifact.

The version name and version code come from `pubspec.yaml`. Increment the build
number for every Play upload; Google Play rejects a reused version code.

## Signing contract

Release lanes on `main`, version tags, and manual dispatch require these
Vault-backed environment variables:

`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
and `ANDROID_KEY_PASSWORD`.

The workflow materializes the keystore only for the build and removes it when
the step exits. Never commit `android/key.properties`, a keystore, or passwords.
Pull request verification builds may use the documented debug-signing fallback,
but those artifacts must not be uploaded to Play.

## Play listing and policy information

- Developer name: **XWork Technologies LLC**.
- Organization website: <https://xworktech.com>.
- Privacy policy: <https://xworktech.com/privacy>.
- Support/contact: <https://xworktech.com/support> and
  <https://xworktech.com/contact>.
- Keep the store listing, Data safety form, target audience, content rating,
  app access instructions, screenshots, and support email aligned with the
  current app behavior before submitting production access.

After the signed AAB passes internal testing, complete Play Console app
content declarations and promote through closed testing before production.
