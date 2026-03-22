import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/ui_feature_manifest.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final featureManifest = await UiFeatureManifestLoader.load();
  runApp(XWorkmateApp(featureManifest: featureManifest));
}
