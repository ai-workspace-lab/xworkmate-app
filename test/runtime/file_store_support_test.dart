import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/file_store_support.dart';

void main() {
  group('file store owner-only permissions', () {
    test('uses chmod only on desktop Unix platforms', () {
      expect(
        shouldApplyUnixOwnerOnlyPermissionsInternal(operatingSystem: 'macos'),
        isTrue,
      );
      expect(
        shouldApplyUnixOwnerOnlyPermissionsInternal(operatingSystem: 'linux'),
        isTrue,
      );
    });

    test('does not require chmod on mobile sandbox platforms', () {
      expect(
        shouldApplyUnixOwnerOnlyPermissionsInternal(operatingSystem: 'ios'),
        isFalse,
      );
      expect(
        shouldApplyUnixOwnerOnlyPermissionsInternal(operatingSystem: 'android'),
        isFalse,
      );
    });

    test('does not require chmod on Windows', () {
      expect(
        shouldApplyUnixOwnerOnlyPermissionsInternal(operatingSystem: 'windows'),
        isFalse,
      );
    });
  });
}
