import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

/// The composer boundary is draggable, but the offset used to live only in
/// widget state — it survived a session switch and died on restart. It is now
/// carried in AppUiState.
void main() {
  group('composer height persistence', () {
    test('round-trips through JSON', () {
      final state = AppUiState.defaults().copyWith(
        assistantComposerHeightAdjustment: 120.5,
      );

      final restored = AppUiState.fromJsonString(state.toJsonString());

      expect(restored.assistantComposerHeightAdjustment, 120.5);
    });

    test('a negative offset survives — the composer can be shrunk too', () {
      final state = AppUiState.defaults().copyWith(
        assistantComposerHeightAdjustment: -80,
      );

      final restored = AppUiState.fromJsonString(state.toJsonString());

      expect(restored.assistantComposerHeightAdjustment, -80);
    });

    test('state written before this field existed still loads', () {
      // The field is deliberately optional rather than schema-bumped:
      // fromJson rejects a version mismatch outright, so a bump would discard
      // the user's saved navigation destinations and gateway targets.
      final legacy = AppUiState.defaults().toJson()
        ..remove('assistantComposerHeightAdjustment');

      final restored = AppUiState.fromJson(legacy);

      expect(restored.assistantComposerHeightAdjustment, 0);
      expect(
        restored.assistantNavigationDestinations,
        AppUiState.defaults().assistantNavigationDestinations,
        reason: 'unrelated state must not be lost',
      );
    });

    test('a corrupt or absurd stored value is clamped, not trusted', () {
      expect(normalizeComposerHeightAdjustment(double.nan), 0);
      expect(normalizeComposerHeightAdjustment(double.infinity), 0);
      expect(normalizeComposerHeightAdjustment(null), 0);
      expect(normalizeComposerHeightAdjustment(999999), 2000);
      expect(normalizeComposerHeightAdjustment(-999999), -2000);
      expect(normalizeComposerHeightAdjustment(64), 64);
    });

    test('a non-numeric stored value falls back to the default', () {
      final json = AppUiState.defaults().toJson();
      json['assistantComposerHeightAdjustment'] = 'not a number';

      final restored = AppUiState.fromJson(json);

      expect(restored.assistantComposerHeightAdjustment, 0);
    });
  });
}
