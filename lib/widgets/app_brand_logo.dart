import 'package:flutter/material.dart';

import '../app/app_metadata.dart';
import '../theme/app_palette.dart';

class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    super.key,
    this.size = 32,
    this.borderRadius = 10,
    this.showShadow = true,
  });

  final double size;
  final double borderRadius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: palette.chromeStroke),
        boxShadow: showShadow ? [palette.chromeShadowLift] : const [],
      ),
      child: Image.asset(
        kProductLogoAsset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.crop_square_rounded,
          color: palette.textSecondary,
          size: size * 0.64,
        ),
      ),
    );
  }
}
