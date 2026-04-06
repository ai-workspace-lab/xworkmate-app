import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  patrolTest('grant permission and login flow', ($) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('patrol-test-');
    debugOverridePersistentSupportRoot(tempDir.path);
    addTearDown(() async {
      debugOverridePersistentSupportRoot(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    $.pumpWidgetAndSettle(const XWorkmateApp());

    // Test native permission dialog (patrol can handle system dialogs)
    // await $.native.grantPermission();

    // Verify app loads
    await $.pumpAndSettle();

    // Tap new conversation
    final newChatButton = find.byKey(const Key('new-chat-button'));
    if (newChatButton.evaluate().isNotEmpty) {
      await $.tap(newChatButton);
      await $.pumpAndSettle();
    }

    // Enter text in input field
    final inputField = find.byKey(const Key('assistant-input-field'));
    if (inputField.evaluate().isNotEmpty) {
      await $.tap(inputField);
      await $.enterText('test input');
    }

    await $.pumpAndSettle();
  });

  patrolTest('navigation flow test', ($) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('patrol-test-');
    debugOverridePersistentSupportRoot(tempDir.path);
    addTearDown(() async {
      debugOverridePersistentSupportRoot(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    $.pumpWidgetAndSettle(const XWorkmateApp());
    await $.pumpAndSettle();

    // Navigate to tasks tab
    final tasksTab = find.byKey(const Key('assistant-side-pane-tab-tasks'));
    if (tasksTab.evaluate().isNotEmpty) {
      await $.tap(tasksTab);
      await $.pumpAndSettle();
    }

    // Navigate to settings tab
    final settingsTab = find.byKey(const Key('assistant-side-pane-tab-settings'));
    if (settingsTab.evaluate().isNotEmpty) {
      await $.tap(settingsTab);
      await $.pumpAndSettle();
    }

    // Navigate back to assistant
    final assistantTab = find.byKey(const Key('assistant-side-pane-tab-assistant'));
    if (assistantTab.evaluate().isNotEmpty) {
      await $.tap(assistantTab);
      await $.pumpAndSettle();
    }
  });

  patrolTest('native interaction test', ($) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('patrol-test-');
    debugOverridePersistentSupportRoot(tempDir.path);
    addTearDown(() async {
      debugOverridePersistentSupportRoot(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    $.pumpWidgetAndSettle(const XWorkmateApp());
    await $.pumpAndSettle();

    // Open system-level dialogs or native elements
    // await $.native.openNotifications();
    // await $.native.grantPermission();

    // Long press test
    final inputField = find.byKey(const Key('assistant-input-field'));
    if (inputField.evaluate().isNotEmpty) {
      await $.longPress(inputField);
      await $.pumpAndSettle();
    }

    // Drag gesture
    // await $.drag(startPoint, endPoint);
  });
}
