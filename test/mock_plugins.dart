import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void mockPlugins() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/package_info'),
    (MethodCall methodCall) async {
      return {
        'appName': 'XWorkmate',
        'packageName': 'com.xevor.xworkmate',
        'version': '1.1.5',
        'buildNumber': '1',
      };
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/device_info'),
    (MethodCall methodCall) async {
      return {
        'computerName': 'Test-Mac',
        'hostName': 'Test-Mac',
        'arch': 'arm64',
        'model': 'MacBookPro18,1',
        'kernelVersion': 'Darwin 21.4.0',
        'osRelease': '21.4.0',
        'activeCPUs': 10,
        'memorySize': 34359738368,
        'cpuFrequency': 3200000000,
      };
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      return '/tmp';
    },
  );
}
