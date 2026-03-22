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
}
