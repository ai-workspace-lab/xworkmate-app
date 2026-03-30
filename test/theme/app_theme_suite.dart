@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  test('AppTheme uses compact mobile typography on iOS and Android', () {
    final iosTheme = AppTheme.light(platform: TargetPlatform.iOS);
    final androidTheme = AppTheme.light(platform: TargetPlatform.android);

    expect(iosTheme.textTheme.displaySmall?.fontSize, 24);
    expect(androidTheme.textTheme.displaySmall?.fontSize, 24);
    expect(iosTheme.textTheme.headlineSmall?.fontSize, AppTypography.titleSize);
    expect(
      androidTheme.textTheme.headlineSmall?.fontSize,
      AppTypography.titleSize,
    );
    expect(
      iosTheme.filledButtonTheme.style?.minimumSize?.resolve({})?.height,
      AppSizes.buttonHeightMobile,
    );
    expect(
      androidTheme.inputDecorationTheme.constraints?.minHeight,
      AppSizes.inputHeight,
    );
  });

  test('AppTheme keeps larger display typography on desktop surfaces', () {
    final desktopTheme = AppTheme.light(platform: TargetPlatform.macOS);

    expect(desktopTheme.textTheme.displaySmall?.fontSize, 28);
    expect(
      desktopTheme.filledButtonTheme.style?.minimumSize?.resolve({})?.height,
      AppSizes.buttonHeightDesktop,
    );
  });

  test('AppTheme matches calm compact workspace baseline tokens', () {
    expect(AppRadius.card, 12);
    expect(AppRadius.input, 12);
    expect(AppRadius.dialog, 12);
    expect(AppRadius.chip, 12);
    expect(AppTypography.sectionSize, 13);
    expect(AppTypography.bodySize, 13);
    expect(AppTypography.compactBodySize, 13);
    expect(AppSizes.buttonHeightDesktop, 30);

    expect(AppTheme.light().colorScheme.primary, const Color(0xFF0058BD));
    expect(
      AppTheme.dark().scaffoldBackgroundColor,
      const Color(0xFF141422),
    );
  });
}
