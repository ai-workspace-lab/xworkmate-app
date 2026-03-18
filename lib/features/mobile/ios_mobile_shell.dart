import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import 'mobile_shell.dart';

@Deprecated('Use MobileShell instead.')
class IosMobileShell extends StatelessWidget {
  const IosMobileShell({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MobileShell(controller: controller);
  }
}
