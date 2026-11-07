import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/app_services.dart';
import 'core/services/alert_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw the first frame immediately. Startup work (notification channels,
  // secure-storage reads, push registration) runs in the background while
  // the splash screen shows: awaiting it here left the phone on a blank
  // launch screen, and a touch during that wait made Android report
  // "app isn't responding". The splash waits for AppServices.ready.
  unawaited(
    AlertService.instance.init().catchError((Object _) {
      // Alerts still work in-app; only the system notification channel is
      // missing until the next start.
    }),
  );
  AppServices.instance.start();

  runApp(const App());
}
