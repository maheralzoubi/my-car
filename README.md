# MyCar (CARDIAG)

A Flutter app that turns a phone + ELM327 Bluetooth OBD-II adapter into a full car diagnostics dashboard, plus an on-demand roadside assistance flow. Dark-themed, fully localized (English/Arabic).

## Features

**Diagnostics (CARDIAG)**
- BLE pairing with ELM327 OBD-II adapters, with auto-detection of likely OBD devices
- Live gauges (RPM, speed, MAP, timing advance) and a 22-icon warning-light grid
- DTC (trouble code) reading with a 5,600+ code database, freeze-frame data, and history
- 0–100 vehicle health score and real-time driving alerts with a Drive Score
- Trip computer (distance, time, avg speed, fuel, efficiency)
- VIN decoding and maintenance tracker
- Live sensor graphing

**Roadside Assistance**
- On-demand towing/roadside request flow with maps and location
- Media capture (photos) attached to a request

**Platform**
- English/Arabic localization throughout
- BLoC-based state management, dark theme, responsive layout via `flutter_screenutil`

See [APP_PAGES_FEATURES.md](APP_PAGES_FEATURES.md) for a full screen-by-screen audit.

## Tech Stack

- **Flutter** / Dart (SDK `^3.9.2`)
- **State management:** `flutter_bloc`
- **Bluetooth:** `flutter_blue_plus` (ELM327 OBD-II over BLE)
- **Maps/location:** `google_maps_flutter`, `geolocator`
- **Charts:** `fl_chart`
- **Persistence:** `shared_preferences`
- **Notifications/audio:** `flutter_local_notifications`, `audioplayers`

## Project Structure

```
lib/
  app/            # MaterialApp setup, routing, theming
  core/            # shared bloc, constants, localization, services, theme, utils
  modules/
    home/          # OBD-II diagnostics module (CARDIAG)
    roadside/      # roadside assistance module
assets/
  dtcmapping.json     # DTC code database (English)
  dtcmapping_ar.json  # DTC code database (Arabic)
  sounds/             # alert sounds
```

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.9+)
- An Android/iOS device or emulator with Bluetooth support to test OBD-II features
- An ELM327 Bluetooth OBD-II adapter (for on-vehicle testing)

### Setup

```bash
flutter pub get
flutter run
```

### Tests

```bash
flutter test
```

## Notes

- OBD/BLE features require a physical device — simulators/emulators cannot pair with a real ELM327 adapter.
- Google Maps requires an API key configured per-platform (Android `AndroidManifest.xml`, iOS `AppDelegate.swift`) before the roadside map screens will render.
