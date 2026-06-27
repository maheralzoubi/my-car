import 'obd_adapter.dart';

/// Accumulates trip statistics by sampling live OBD data every poll cycle.
///
/// Call [start] when OBD connects, [stop] when it disconnects, [reset] to
/// begin a new trip. [addSample] is called automatically from the dashboard
/// via a StreamSubscription on [OBDService.instance.liveDataStream].
class TripService {
  TripService._();
  static final TripService instance = TripService._();

  bool _running = false;
  DateTime? _startTime;
  DateTime? _lastSample;

  double _distanceKm       = 0;
  double _sumSpeedKmh      = 0;
  int    _movingSamples    = 0;
  double _estimatedFuelL   = 0;

  // ── Public API ────────────────────────────────────────────────────────────

  bool   get isRunning    => _running;
  double get distanceKm   => _distanceKm;
  double get fuelUsedL    => _estimatedFuelL;

  Duration get elapsed =>
      _running && _startTime != null
          ? DateTime.now().difference(_startTime!)
          : Duration.zero;

  double get avgSpeedKmh =>
      _movingSamples > 0 ? _sumSpeedKmh / _movingSamples : 0;

  /// L/100 km — only meaningful once some distance has been covered.
  double get fuelEfficiencyL100km =>
      _distanceKm > 0.5 ? (_estimatedFuelL * 100) / _distanceKm : 0;

  void start() {
    _running     = true;
    _startTime   = DateTime.now();
    _lastSample  = DateTime.now();
    _distanceKm       = 0;
    _sumSpeedKmh      = 0;
    _movingSamples    = 0;
        _estimatedFuelL   = 0;
  }

  void stop()  => _running = false;

  void reset() {
    _distanceKm       = 0;
    _sumSpeedKmh      = 0;
    _movingSamples    = 0;
        _estimatedFuelL   = 0;
    _startTime        = DateTime.now();
    _lastSample       = DateTime.now();
  }

  /// Feed each live-data snapshot from [OBDService.liveDataStream].
  void addSample(OBDLiveData data) {
    if (!_running) return;

    final now = DateTime.now();
    final dtSec = _lastSample != null
        ? now.difference(_lastSample!).inMilliseconds / 1000.0
        : 0.0;
    _lastSample = now;

    if (dtSec <= 0 || dtSec > 10) return; // ignore stale / first sample

    final speed = data.speedKmh ?? 0;
    final load  = (data.engineLoad ?? 30) / 100.0;

    // Distance: km/h × seconds / 3600 = km
    _distanceKm += speed * dtSec / 3600.0;

    // Average speed (only while moving)
    if (speed > 2) {
      _sumSpeedKmh += speed;
      _movingSamples++;
    }
    
    // Fuel estimate: rough model using engine load as a proxy for fuel flow.
    // Baseline: 8 L/100 km at 100% load. Scales with load fraction and speed.
    // This is intentionally approximate — a MAF-based estimate would be precise
    // but MAF (PID 0110) is not supported on many cheap ELM327 adapters.
    if (speed > 0) {
      final baseL100km = 8.0;
      final adjustedL100km = baseL100km * (0.4 + 0.6 * load);
      _estimatedFuelL += adjustedL100km * (speed * dtSec / 3600.0) / 100.0;
    } else if (load > 0.1) {
      // Idling: ~0.5 L/hr
      _estimatedFuelL += 0.5 * dtSec / 3600.0;
    }
  }
}
