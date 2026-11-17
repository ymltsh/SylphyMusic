import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'rp_management_page.dart';

/// Compatibility navigation entry: v21 replaces the obsolete memory viewer.
class PenpalMemoryPage extends StatelessWidget {
  const PenpalMemoryPage({super.key, required this.app});
  final SylphyApp app;

  @override
  Widget build(BuildContext context) => RpManagementPage(app: app);
}
