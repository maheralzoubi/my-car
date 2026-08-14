# MyCar (CARDIAG) — Redesign Plan

This is the working plan for redesigning every screen in the app. It picks up where [APP_PAGES_FEATURES.md](APP_PAGES_FEATURES.md) (the functional audit) left off — that doc describes *what's broken*, this one describes *what to build instead* and in what order.

Two problems today, both in scope:
1. **No shared design system** — every screen re-declares its own `Color(0xFF...)` literals, gradients, and card styles instead of using `AppColors`/`AppSizes` (`lib/core/constants/`). The result is visually inconsistent (e.g. DTC Lookup still uses default Material light styling while everything else is a dark cyan/orange "CARDIAG" look).
2. **No shared chrome** — there's no persistent `AppShell`/bottom-nav scaffold, so the 5-tab nav only exists inside Dashboard and every tab switch is a full page push.

Redesigning "page by page" without fixing those two first means re-doing work later. So the plan below is: **build the system → build the shell → redesign screens in priority order, screen by screen, against that system.**

---

## 1. Design System (build first)

Establish one source of truth in `lib/core/theme/` + `lib/core/constants/app_colors.dart` and require every screen to consume it — no local hex literals.

### Palette
Current brand colors already exist in `AppColors` but aren't consistently used. Redesign should standardize on:

| Token | Value | Usage |
|---|---|---|
| `backgroundDark` / `backgroundDarkBlue` | `#0D0D0D` / `#0A1929` | Screen background gradient |
| `accentCyan` | `#00D9FF` | Primary accent — active states, gauges, CTAs |
| `accentOrange` | `#FF6B35` | Secondary accent — warnings, alerts |
| `surfaceDark` / `surfaceDarkElevated` | `#1C1B1F` / `#2D2D30` | Cards, sheets, elevated surfaces |
| `textLight` | `#E8EAED` | Primary text on dark backgrounds |
| `success` / `error` / `errorLight` | existing | Status colors (health score, DTC severity) |

**Decision needed:** the light `ColorScheme` in `AppTheme.light` uses an unrelated Material-purple palette (`#6750A4` etc.) that no screen actually uses, since `themeMode` is forced to dark app-wide. Redesign should either delete the unused light theme or repurpose those tokens — don't maintain two palettes if only one ships.

### Typography & spacing
- Use `AppSizes` spacing/radius tokens (`space4`–`space64`, `radiusXs`–`radiusFull`) everywhere; stop hardcoding `.h`/`.w` magic numbers for padding.
- Define a small `AppTextStyles` set (display/title/body/caption × the two accent colors) so headers stop being redeclared per-screen with slightly different weights/sizes.

### Shared components to extract
These patterns are currently copy-pasted across most screens — pull each into `lib/core/widgets/` (or per-module `presentation/widgets/`) once, then reuse:

| Component | Replaces |
|---|---|
| `AppScaffold` / gradient background wrapper | The dark-gradient `Container` + `Scaffold` boilerplate at the top of nearly every screen |
| `AppCard` | The repeated rounded-surface-container-with-border pattern |
| `SectionHeader` | Repeated "icon + title + optional trailing action" row |
| `AppShell` (bottom nav) | Dashboard's inline nav bar — see §2 |
| `StatusBadge` | DTC severity pills, request-status pills, connection-status pills (currently each hand-rolled) |
| `EmptyState` / `ErrorState` | Missing today in Location Picker, Price Estimate, Request History |

---

## 2. Navigation Shell (build second)

Extract `AppShell` with an `IndexedStack` over the 5 primary tabs (Home/Scan/Smart Key/History/Settings), so:
- Tab state persists across switches (no more full `Navigator.pushNamed` per tab)
- Every primary screen shares identical bottom-nav chrome instead of only Dashboard having one
- Non-primary screens (Code Detail, Solution, Settings sub-pages, all of Roadside) keep pushing normally on top of the shell

This is a prerequisite for the Dashboard redesign in §3, since today's nav bar lives inside it.

---

## 3. Per-Screen Redesign Plan

Ordered by priority. Priority = (visual inconsistency + functional brokenness + how central the screen is to daily use). Status icons carry over from the audit: 🔴 needs rebuild · 🟡 needs visual pass · 🟢 mostly on-system already.

### Phase 1 — Foundation screens (blocks everything else)
| Screen | Redesign scope |
|---|---|
| **AppShell (new)** | Build the persistent bottom-nav shell described in §2 |
| **Splash** | Keep the animated concept, restyle onto the shared design tokens, rename `spalchScreen`→`splashScreen` |
| **Auth (Login/Signup)** | Redesign form layout to remove fixed `500.h` height (intrinsic/flexible sizing); real "Forgot password" flow gets a real screen/sheet |
| **Mode Selection** | Already the most polished screen — treat as the **visual reference** for the rest of the redesign (its gradient/animation/card language is the target look) |

### Phase 2 — Diagnostics core (used every session)
| Screen | Redesign scope |
|---|---|
| **Dashboard** | Full rebuild: decompose into `GaugeCluster`, `WarningLightGrid`, `TripComputerCard`, `VinCard`, `MaintenanceBanner` widgets. Replace emoji warning icons with real `Icon`/SVG assets. Redesign the health-score display as a continuous gauge, not a 5-bucket lookup badge. |
| **Connection (BLE scan)** | Consolidate the 4 parallel per-state switch statements into one `ConnectionStateConfig` (icon/color/message/subtitle) driving a single state-driven layout |
| **Diagnostic Codes** | Restyle filter chips/cards onto shared `AppCard`/`StatusBadge`; keep animated slide-in |
| **Code Detail** | Redesign the "image gallery" — replace emoji placeholders with a real image/diagram slot or remove the section entirely; layout otherwise reusable |
| **Solution** | Needs actual content design (step-by-step repair layout: numbered steps, tools list, difficulty/time estimate) — currently a stub with no design to reference |
| **DTC Lookup** | Currently the one screen still on default Material light `AppBar` — bring onto the dark design system (highest visual-inconsistency screen in the app) |
| **History** | Make entries tappable (card → `CodeDetailScreen`); restyle stat card onto `AppCard` |
| **Live Graph** | Add a "Normalized" axis caption; otherwise minor polish only |
| **Maintenance** | Lowest-priority visual pass — already clean |

### Phase 3 — Secondary features
| Screen | Redesign scope |
|---|---|
| **Settings** | Redesign toggle rows to clearly distinguish "wired" vs "coming soon" states (many toggles are currently local-only with no visual cue) |
| **Dash Cam Settings** | Move off `MaterialPageRoute` onto the shell/named-route pattern; design a real settings-persistence UI |
| **Profile / Edit Profile** | Full redesign once real user/vehicle data is wired — avatar picker, saved-vehicles list, achievements grid all need a real empty/loading/populated state design, not just static mock cards |
| **Smart Key** | Either design a clear "preview/demo" treatment (badge/banner distinguishing it from real hardware control) or hold redesign until real BLE command wiring lands |
| **Parent Mode** | Currently orphaned (no entry point) — decide product-side whether this ships before investing redesign effort; if it ships, replace the painted fake map with a real `google_maps_flutter` view matching the Roadside module's map styling |
| **Video Tutorials / Player / Upload** | Needs a real video-player UI (thumbnail + scrubber + controls) once `video_player` is integrated; upload flow needs a real progress/success design, not simulated |

### Phase 4 — Roadside module
| Screen | Redesign scope |
|---|---|
| **Roadside Home** | Restyle service-picker grid onto shared `AppCard`; either compute header stat chips from real data or visually mark them as illustrative |
| **Location Picker** | Add visible permission-error state (snackbar/dialog) instead of silent failure; design the `deniedForever` → app-settings deep link prompt |
| **Price Estimate** | Fix `Image.asset`→`Image.file` (photos currently never render); add a gallery-picker option alongside camera; design a visible submission-error state |
| **Searching Driver** | Keep the radar animation; remove/relabel the hardcoded "12 drivers online" fake stat; design a timeout/fallback state |
| **Tracking** | Wire the call-driver button to a real `tel:` action with a proper button state; extract the shared dark-map style so Tracking and Location Picker render identically |
| **Rating** | Fix the "Skip & Done" bug (must not submit a hidden 5-star review) as part of redesigning that button's states (rated vs. skip) |
| **Request History** | Design real empty/error states (currently a failed fetch looks identical to "no requests yet"); make cards tappable to reopen a receipt |

---

## 4. Definition of done (per screen)

A screen's redesign isn't complete until:
- [ ] Zero raw `Color(0xFF...)` literals — everything through `AppColors`
- [ ] Zero raw spacing/radius numbers — everything through `AppSizes`
- [ ] Uses shared components (`AppCard`, `SectionHeader`, `StatusBadge`, etc.) instead of a private reimplementation
- [ ] No emoji-as-icon usage
- [ ] Full `context.tr()` localization coverage (EN + AR)
- [ ] Has an explicit empty/loading/error state where the screen depends on async data
- [ ] Lives on the `AppShell` if it's one of the 5 primary tabs; otherwise pushes correctly via named `AppRoutes`

---

## 5. Sequencing note

Phases 1–2 should land together — the design system and shell only pay off once the highest-traffic screens (Dashboard, Diagnostic Codes) sit on top of them, and Mode Selection already gives Phase 1 a visual target to copy rather than invent from scratch. Phases 3–4 can proceed screen-by-screen independently once the system is in place.
