import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/ui_feature_manifest.dart';
import 'runtime/enterprise_http_overrides.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnterpriseHttpOverrides.install();
  final featureManifest = await UiFeatureManifestLoader.load();
  runApp(XWorkmateApp(featureManifest: featureManifest));
}
