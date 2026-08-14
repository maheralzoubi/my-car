# MyCar (CARDIAG) — Full App, Pages & UI/UX Audit

Single Flutter app (`mycar`) containing **two feature modules**:

1. **Home module** — OBD-II car diagnostics, dashboard, maintenance, media (branded "CARDIAG")
2. **Roadside module** — on-demand roadside assistance / towing request flow

This doc catalogs every screen, its current features, and concrete UI/UX improvement recommendations, so it can double as a design/cleanup backlog.

> Legend: 🟢 fully wired to real data/services · 🟡 partially wired / mixed · 🔴 mock, stub, or non-functional

---

## 0. App Shell & Navigation

| Item | Detail |
|---|---|
| Entry | `lib/app/app.dart` → `MaterialApp` with named routes, dark theme forced (`themeMode: ThemeMode.dark`), `ScreenUtilInit` (design size 390×844), full EN/AR localization + `LocaleBloc` |
| Initial route | `AppRoutes.splash` |
| State mgmt | `flutter_bloc` — `LocaleBloc` (app-wide), `RoadsideBloc` (app-wide, single instance) |
| Routing | Named routes (`AppRoutes`) for most screens; **one exception** — `DashCamSettingsScreen` uses a raw `MaterialPageRoute`, breaking the convention |

**🔴 Critical UX gap: there is no persistent bottom-navigation shell.** The 5-item nav bar (Home/Scan/Smart Key/History/Settings) is drawn *inside* `DashboardScreen` only, and each tap does a full `Navigator.pushNamed` rather than swapping a tab body — so switching tabs feels like drilling into new pages (with back stacks piling up) instead of true tab switching, and no other screen shows this nav bar at all. **Recommendation:** extract a shared `AppShell`/`BottomNavScaffold` with an `IndexedStack` so tab state persists and every primary screen shares one consistent chrome.

`home_page.dart` (`HomePage`) is a vestigial leftover screen (welcome header + counter-card + roadside banner) not part of the real navigation flow (real entry is Splash → Auth → Mode Selection → Dashboard/Roadside) — candidate for deletion.

---

## 1. Home Module (CARDIAG — OBD-II Diagnostics)

### 1.1 Splash Screen 🟡
`spalchScreen/spalch_screen.dart` *(typo in folder name: "spalch")*
- Branded intro: custom-painted car illustration, scan-line sweep, gradient "CARDIAG" title, animated loading bar. 5 concurrent `AnimationController`s.
- Routes to Mode Selection or Auth based on stored `is_logged_in` flag after 5s.
- **UI/UX fixes:** rename folder `spalchScreen`→`splashScreen`; localize "INITIALIZING SYSTEM..." / "PROFESSIONAL DIAGNOSTICS"; consider skip-tap-to-continue for returning users.

### 1.2 Auth Screen 🔴 (demo-only)
`authScreen/auth_screen.dart`
- Login/Signup via `TabBar`, gradient branding, animated logo.
- **Security/UX issue:** login form is **pre-filled with hardcoded demo credentials** (`maher@gmail.com` / `maher1997`) and validated against constants in source — must be replaced with real auth before any release.
- "Forgot password" is a dead button (`onPressed: () {}`).
- Fixed `SizedBox(height: 500.h)` risks overflow on small screens / large system font sizes.
- **Fixes:** real auth backend, implement forgot-password, replace fixed heights with intrinsic/flexible sizing, move brand strings into localization.

### 1.3 Mode Selection Screen 🟢 (most polished screen)
`modeSelectionScreen/mode_selection_screen.dart`
- Post-login hub: choose **Car Diagnostics** vs **Roadside Assistance**, animated background (orbiting dots, pulsing glow), press-scale mode cards, exit-confirmation dialog on back.
- **UX note:** 3 always-running `AnimationController`s (entrance/pulse/orbit) — verify battery/perf impact on low-end devices since orbit+pulse loop indefinitely while idle on this screen.

### 1.4 Connection Screen 🟢
`connectionScreen/connection_screen.dart`
- BLE scan/pair flow for ELM327 OBD adapters; state machine drives status icon/CTA text; OBD-likely devices auto-detected and floated to top with badge + RSSI bars; animated radar pulse while scanning.
- **Fixes:** consolidate the four separate per-state switch statements (`_accentColor`, icon, message, subtitle) into one config object/map; add a distinct "wrong protocol / unsupported adapter" error state; surface the location-permission rationale in UI copy, not just code comments.

### 1.5 Dashboard Screen 🟢 (core hub, 2,100+ lines — needs decomposition)
`dashboardScreen/dashboard_screen.dart` + `obd_gauge.dart`
- Live OBD polling → 22-icon warning-light grid (DTC + live-threshold derived), 0–100 vehicle health score, custom arc gauges (RPM/Speed), trip computer (distance/time/avg speed/fuel/efficiency/Drive Score), in-app critical/warning alert banners, freeze-frame + pending-code bottom sheet with "YouTube Fix" deep link, VIN decode card, maintenance-due banner, quick-scan & video-tutorial CTA cards, houses the app's only bottom nav bar.
- **Fixes (priority):**
  - Split into smaller widgets/files (gauges, warning grid, trip card, VIN card, sensor tiles) — 2,100 lines in one file is unmaintainable and slows iteration.
  - `_buildRecentScansSection()` is a dead placeholder always showing "No scans yet" despite `DtcHistoryService` having real data — wire it up.
  - Replace emoji-as-icons (⚠️🔋🛢️ etc.) with real `Icon`/`SvgPicture` widgets for consistent rendering + accessibility (screen readers can't label emoji meaningfully).
  - Extract repeated hardcoded hex colors into `AppColors` constants (dozens of literal `Color(0xFF...)` duplicates).
  - Make health-score formula continuous/weighted by severity rather than a 5-bucket lookup table.

### 1.6 Diagnostic Codes Screen 🟢
`diagnosticCodesScreen/diagnostic_codes_screen.dart`
- Full DTC list (confirmed + pending) with system/severity classification, emissions-readiness monitor panel, filter chips, animated slide-in cards with freeze-frame data, export-report action, clear-codes flow.
- **Fixes:** `_exportReport()` calls `Share.shareXFiles([], text:...)` — passes an empty file list; either generate a real shareable file (PDF/txt) or switch to `Share.share(text)`. Fill in missing `context.tr()` calls (several literals still hardcoded English). The "Arabic" description fields passed to Code Detail are currently duplicated from the English string — needs real translated content.

### 1.7 Code Detail Screen 🔴 (fake data)
`diagnosticCodesScreen/code_detail_screen.dart`
- Severity-colored detail card, Cause/Cost/Repair-Time tiles, emoji "image gallery," related-codes chips, CTA to Solution.
- **Fixes:** Cause/Cost/Repair-Time/Related-Codes are **static regardless of which code is shown** — must be code-specific (join with `DtcRepository`). Replace emoji gallery with real diagnostic images or remove the section. Wire up the no-op share icon or remove it. Add localization (currently none).

### 1.8 Solution Screen 🔴 (unfinished stub)
`diagnosticCodesScreen/solution_screen.dart`
- Literally placeholder copy telling a future dev to "replace this section" — needs real step-by-step repair content before shipping.

### 1.9 DTC Lookup Page 🟢 (visually inconsistent)
`dtc_lookup_page.dart`
- Manual code→description lookup via `DtcRepository`; well-localized, correct async/context handling.
- **Fix:** only screen using default Material `AppBar`/light styling — restyle to match the app's dark-gradient design system.

### 1.10 History Screen 🟡
`historyScreen/history_screen.dart`
- Scan-history log with stats card, filters, animated entries.
- **Fix:** entries are **not tappable** — should deep-link into `CodeDetailScreen` like `DiagnosticCodesScreen` does, for consistency and utility.

### 1.11 Live Graph Screen 🟢
`liveGraphScreen/live_graph_screen.dart`
- Real-time multi-channel line chart (`fl_chart`), 10 selectable sensor channels normalized to a shared 0–100% axis, live legend values.
- **Fix (minor):** Y-axis shows bare "%" with no indication it's normalized — add an axis caption ("Normalized") so it's self-explanatory without needing to touch the chart.

### 1.12 Maintenance Screen 🟢 (clean, no major issues)
`maintenanceScreen/maintenance_screen.dart`
- Mileage tracking, interval-based service items, overdue/due-soon status badges, log-service flow.

### 1.13 Parent Mode Screen 🔴 (orphaned + fully mocked)
`parentModeScreen/parent_mode_screen.dart`
- Teen-driver tracking: fake "map" (painted grid, no real map SDK), speed badge, geo-fence/tracking toggles.
- **Fixes:** route (`AppRoutes.parentMode`) exists but **no screen links to it** — either surface it (e.g., from Mode Selection or Settings) or remove the dead route. Replace the painted grid with a real map (Google Maps, consistent with the Roadside module). `currentSpeed = 120` is hardcoded above the default `speedLimit`, so the "Speed Alert!" badge is **always on** — confusing/broken by default. Add localization (currently none).

### 1.14 Profile & Edit Profile Screens 🔴 (fully mocked)
`profileScreen/profile_screen.dart`, `profileScreen/edit_profile_screen.dart`
- Profile summary, stats, saved vehicles, achievements; edit form with avatar/password dialogs.
- **Fixes:** all data hardcoded ("John Doe", Toyota Camry/Honda Civic) and disconnected from `AuthScreen`'s login identity — needs a real user/vehicle data source. Avatar picker options and password-change "Update" are non-functional stubs. Save button only simulates a 2s delay with no persistence. Add localization (currently none on Profile; partial on Edit Profile).

### 1.15 Settings Screen 🟡 + Dash Cam Settings 🔴
`settingsScreen/settings_screen.dart`, `settingsScreen/dash_cam_settings_screen.dart`
- Settings hub: profile shortcut, toggles, language (real, wired to `LocaleBloc`), units, about, logout.
- **Fixes (priority):**
  - **Logout is broken** — confirm button only closes the dialog; it never clears `is_logged_in` in `SharedPreferences` nor navigates to Auth. Users can never actually sign out. Fix immediately.
  - Notifications/Auto Scan/Dark Mode/Sound Effects/Units toggles are local-only `setState`, no persistence or real effect — either implement or clearly mark "coming soon."
  - App Version is hardcoded `v1.0.0` — read from `package_info_plus` instead.
  - Dash Cam settings have no persistence (reset every time the screen reopens) and no real hardware/service integration; also reached via raw `MaterialPageRoute` instead of a named route — convert to `AppRoutes.dashCamSettings` usage everywhere.

### 1.16 Smart Key Screen 🔴 (fully simulated)
`smartKeyScreen/smart_key_screen.dart`
- Virtual key fob: lock/unlock/start-engine buttons, pulsing car illustration, "Connected" badge.
- **Fixes:** entirely local boolean state, no real BLE/RF command sent and not tied to `OBDService`'s actual connection status — the "Connected" badge can mislead users into thinking the fob works when the vehicle is actually disconnected. Wire real state or clearly label as a preview/demo feature. Climate & Find-Car quick actions are non-functional.

### 1.17 Video Tutorials, Player & Upload Screens 🔴 (prototype-only)
`videoTutorialsScreen/*.dart`
- Browse/filter tutorial library, fake video player (emoji thumbnail, non-functional slider), mock upload flow with simulated progress.
- **Fixes:**
  - Search bar has no `onChanged` wired — typing does nothing.
  - No real video playback (`video_player`/similar package needed).
  - Upload flow doesn't actually add the new tutorial to the list — published videos vanish.
  - File/thumbnail pickers in Upload are non-functional placeholders (need `image_picker`/`file_picker`).
  - Bookmark toggles don't persist and there's no "saved" filter view despite the bookmark icon implying one exists.
  - Add localization (currently mostly absent across all three screens).

---

## 2. Roadside Assistance Module

**Flow:** Home → Location Picker → Price Estimate → Searching Driver → Tracking → Rating → (reset to Home). History is a separate branch off Home.

### 2.1 Roadside Home Screen 🟡
`roadside_home_screen.dart`
- Service picker grid (6 `ServiceType`s: Flatbed Towing, Battery Jump, Tire Repair, Car Towing, Battery Replacement, Fuel Delivery), header stat chips (avg wait/certified drivers/rating).
- **Fix:** header stats are hardcoded marketing copy, not real metrics — either compute from real data later or label as illustrative.

### 2.2 Location Picker Screen 🟡
`location_picker_screen.dart`
- Google Map with fixed center pin, GPS "my location" FAB, bottom confirm sheet.
- **Fixes:** reverse geocoding is **fully mocked** (shows raw lat/lng, comment explicitly says "replace with geocoding package when API key ready") — high priority once a Maps/Geocoding API key is available. Location permission failures are silently swallowed (`catch (_) {}`) with zero user feedback — add a snackbar/dialog, and handle `deniedForever` explicitly (deep-link to app settings). Localize "Set Your Location" / "Confirm Location."

### 2.3 Price Estimate Screen 🟡
`price_estimate_screen.dart`
- Service summary, location card, price breakdown, notes field, camera-only photo picker, submit CTA.
- **Fixes (priority):**
  - **Bug:** captured photos use `Image.asset(path)` instead of `Image.file(path)` — real camera photos will never render (silently masked by the error builder, showing a placeholder icon instead).
  - Price breakdown math is inconsistent — a hardcoded `$5` "platform fee" line doesn't reconcile with how the displayed total is actually computed; centralize fee logic into one named constant/model used everywhere instead of the `+ 5` magic number repeated across 4 screens.
  - Add a gallery option alongside camera-only capture.
  - Surface `state.error` from a failed submission (currently captured by the bloc but never displayed).

### 2.4 Searching Driver Screen 🟢 (well-animated, but fake stats)
`searching_driver_screen.dart`
- Radar/pulse animation while the mock backend assigns a driver.
- **Fixes:** "12 drivers online" / "< 5 km" radius are hardcoded fake stats presented as live data — remove or clearly back with real numbers. Add a timeout/fallback message in case matching stalls.

### 2.5 Tracking Screen 🟡
`tracking_screen.dart`
- Live map with animated driver/customer markers + route polyline, status banner, driver info card with ETA/price/service chips.
- **Fixes:** **Call-driver button is a no-op** (`onTap: () {}`) — wire to `url_launcher` tel: intent. Cancel is only available during one status (`driverEnRoute`) — reconsider allowing cancel earlier. ETA uses a rough haversine/speed heuristic duplicated from the mock repo — centralize once a real routing API is used. Extract the duplicated `_darkMapStyle` constant (also duplicated in Location Picker) into a shared file.

### 2.6 Rating Screen 🔴 (functional bug)
`rating_screen.dart`
- Success animation, receipt summary, 5-star rating + optional review.
- **Fix (priority, real bug):** the button that reads **"Skip & Done"** still submits an implicit 5-star rating (`_stars == 0 ? 5 : _stars`) — a user trying to skip unknowingly leaves a fake perfect review. Make skip actually skip (no `SubmitRating` call), and localize the remaining hardcoded strings (headings, receipt labels, star adjectives, review hint).

### 2.7 Request History Screen 🔴 (data bug — always empty in practice)
`request_history_screen.dart`
- List of past requests with status pill, price, rating badge.
- **Fix (priority, real bug):** this screen reads from `RoadsideService.instance.repository`, a **different repository instance** than the one the active `RoadsideBloc` uses (`app.dart` constructs its own separate `MockRoadsideRepository`) — so completed requests from the real flow never appear here. Point both at the same repository instance (inject via the bloc or a shared singleton). Also add `FutureBuilder` error handling (currently a failed fetch silently looks like "no requests yet"), and make history cards tappable to re-view a receipt.

---

## 3. Cross-Cutting UI/UX Recommendations (apply app-wide)

Ranked roughly by impact:

1. **Fix the two real functional bugs first:** Settings logout (never signs out), Rating screen's fake "Skip" (submits a hidden 5-star review), Roadside history reading from the wrong repository instance, and `Image.asset`→`Image.file` for captured photos.
2. **Build one shared `AppShell`** with persistent bottom navigation (`IndexedStack`) so all primary screens (Dashboard/Scan/Smart Key/History/Settings) share consistent chrome instead of each re-implementing (or omitting) it.
3. **Consolidate the design system:** extract the repeated dark-gradient background, cyan/orange accent, card style, and header-row pattern into shared theme constants/widgets (`AppColors`, `AppGradients`, `SectionHeader`, `AppCard`) — dozens of raw hex-literal duplicates exist today (e.g. `Color(0xFF00D9FF)` repeated across Dashboard, Auth, Smart Key, Connection, etc.).
4. **Full localization sweep:** `context.tr()` coverage is inconsistent — Profile, Edit Profile, Parent Mode, Code Detail, Solution, and the Video Tutorials trio are largely un-localized while Maintenance/History/Diagnostic Codes/Settings/Mode Selection are solid. Since the app already ships EN/AR support, finish the sweep so nothing silently stays in English for Arabic users.
5. **Replace emoji-as-icon usage** (warning grid, achievements, tools & parts, thumbnails) with real icon assets/`Icon` widgets for visual consistency across platforms/fonts and for screen-reader accessibility.
6. **Decompose oversized files** — `dashboard_screen.dart` (2,100+ lines) most urgently, but most screens would benefit from extracting repeated card/tile builders into `presentation/widgets/` (the Roadside module's `widgets/` folder is currently empty despite every page reimplementing its own private widgets inline).
7. **Replace prototype-only features with either real integrations or explicit "Coming Soon" states**, rather than shipping silent no-ops: Smart Key (fake fob), Video Player/Upload (no real media), Parent Mode (fake map/GPS), Profile (fake account data), Dash Cam Settings (no persistence), Roadside reverse-geocoding (no Geocoding API yet). Users tapping a broken-looking button (share icons, call button, forgot-password, add-vehicle, climate/find-car) is worse for trust than a clearly labeled placeholder.
8. **Add missing error/empty states** where currently absent: Location Picker's silent permission failures, Price Estimate's unsurfaced submission errors, Request History's swallowed fetch errors.
9. **Standardize routing** — eliminate the one `MaterialPageRoute` usage (Dash Cam Settings) in favor of the app's named-route (`AppRoutes`) convention everywhere, and either link or remove the orphaned `parentMode` route.
10. **Centralize magic numbers/business logic** duplicated across files: the roadside `+ 5` platform fee (4 screens), the dark map JSON style (2 screens), and the haversine ETA formula (2 places) should each live in one shared location.

---

## 4. Screen Inventory (quick reference)

| # | Screen | Module | Route | Status |
|---|---|---|---|---|
| 1 | Splash | Home | `splash` | 🟡 |
| 2 | Auth (Login/Signup) | Home | `auth` | 🔴 demo creds |
| 3 | Mode Selection | Home | `modeSelection` | 🟢 |
| 4 | Home (vestigial) | Home | `home` | 🔴 unused |
| 5 | Connection (BLE scan) | Home | `connectionscreen` | 🟢 |
| 6 | Dashboard | Home | `dashboard` | 🟢 needs refactor |
| 7 | Diagnostic Codes | Home | `diagnosticCodes` | 🟢 |
| 8 | Code Detail | Home | `codeDetail` | 🔴 fake data |
| 9 | Solution | Home | `solution` | 🔴 stub |
| 10 | DTC Lookup | Home | `dtcLookup` | 🟢 (style outlier) |
| 11 | History | Home | `history` | 🟡 not tappable |
| 12 | Live Graph | Home | `liveGraph` | 🟢 |
| 13 | Maintenance | Home | `maintenance` | 🟢 |
| 14 | Parent Mode | Home | `parentMode` | 🔴 orphaned/mocked |
| 15 | Profile | Home | `profile` | 🔴 mocked |
| 16 | Edit Profile | Home | `editProfile` | 🔴 mocked |
| 17 | Settings | Home | `settings` | 🟡 logout broken |
| 18 | Dash Cam Settings | Home | (MaterialPageRoute) | 🔴 no persistence |
| 19 | Smart Key | Home | `smartKey` | 🔴 simulated |
| 20 | Video Tutorials | Home | `videoTutorials` | 🔴 prototype |
| 21 | Video Player | Home | `videoPlayer` | 🔴 fake playback |
| 22 | Upload Video | Home | `uploadVideo` | 🔴 non-functional |
| 23 | Roadside Home | Roadside | `roadside` | 🟡 |
| 24 | Location Picker | Roadside | (pushed) | 🟡 mock geocoding |
| 25 | Price Estimate | Roadside | (pushed) | 🟡 photo bug |
| 26 | Searching Driver | Roadside | (pushed) | 🟢 fake stats |
| 27 | Tracking | Roadside | (pushed) | 🟡 call button dead |
| 28 | Rating | Roadside | (pushed) | 🔴 skip bug |
| 29 | Request History | Roadside | (pushed) | 🔴 data bug |

---

*Generated from a full read of every screen file under `lib/modules/home/presentation/pages/` and `lib/modules/roadside/presentation/pages/` plus the roadside bloc/data layer and app routing config, as of 2026-07-06.*
