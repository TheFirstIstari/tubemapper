import 'dart:async';
import 'package:geolocator/geolocator.dart';

import 'models.dart';
import 'sensor_recorder.dart';

/// Monitors location and triggers journey recording when the user
/// enters a station geofence.
class GeofenceTrigger {
  final SensorRecorder _recorder;
  final List<Station> _stations;
  StreamSubscription<Position>? _positionSub;
  bool _isMonitoring = false;

  String? _currentJourneyStartStation;
  bool _hasStartedJourney = false;
  bool _wasInStation = false;

  // ponytail: 100m radius. Tune based on GPS accuracy.
  static const double _geofenceRadiusM = 100.0;

  /// How close to a station the user needs to be to trigger.
  static const double _triggerDistanceM = 80.0;

  GeofenceTrigger(this._recorder, this._stations);

  bool get isMonitoring => _isMonitoring;
  bool get hasActiveJourney => _hasStartedJourney;

  Future<void> start() async {
    if (_isMonitoring) return;

    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
      ),
    ).listen(_onPosition);
    _isMonitoring = true;
  }

  void _onPosition(Position pos) {
    // Find closest station
    Station? closest;
    double minDist = double.infinity;

    // ponytail: linear scan over all stations (~272 for LU). O(n) is fine.
    // Use spatial index (quadtree) if the app ever supports 10k+ stations.
    for (final station in _stations) {
      final dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        station.lat, station.lon,
      );
      if (dist < minDist) {
        minDist = dist;
        closest = station;
      }
    }

    if (closest == null) return;

    final isAtStation = minDist < _triggerDistanceM;
    final isInStationHard = minDist < _geofenceRadiusM;

    // Entering station from outside → start journey
    if (isAtStation && !_wasInStation && !_hasStartedJourney) {
      _recorder.startJourney(closest.id);
      _hasStartedJourney = true;
      _currentJourneyStartStation = closest.id;
    }

    // Entering a different station while journey is active → end
    if (isAtStation &&
        _hasStartedJourney &&
        closest.id != _currentJourneyStartStation) {
      _recorder.stopJourney(endStationId: closest.id);
      _hasStartedJourney = false;
      _currentJourneyStartStation = null;
    }

    _wasInStation = isInStationHard;
  }

  void stop() {
    _positionSub?.cancel();
    _positionSub = null;
    _isMonitoring = false;
    if (_hasStartedJourney) {
      _recorder.stopJourney();
      _hasStartedJourney = false;
    }
  }

  void dispose() {
    stop();
  }
}
