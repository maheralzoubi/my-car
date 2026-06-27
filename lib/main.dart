import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/alert_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlertService.instance.init();
  runApp(const App());
}
