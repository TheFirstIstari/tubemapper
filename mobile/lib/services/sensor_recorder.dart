import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sensors_plus/sensors_plus.dart';

import 'models.dart';

/// Records accelerometer + gyroscope data, detects walking,
/// and uploads completed traces to the render server.
///
/// ponytail: foreground only. Background recording happens via
/// geofence location updates (keeps app alive on iOS via location background mode).
/// Add native foreground service on Android when background recording matters.
class SensorRecorder {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;

  final List<SensorSample> _samples = [];
  final List<GpsFix> _gpsFixes = [];
  final List<String> _stationSequence = [];

  bool _isRecording = false;
  String? _currentJourneyId;
  final String _networkId = 'london-underground';

  // Cadence detection state
  double _lastPeakTime = 0;
  int _peakCount = 0;

  String _currentMotionClass = 'unknown';

  String _deviceId;
  String _serverUrl;

  // Callback when recording state changes
  void Function(bool isRecording)? onRecordingChanged;

  SensorRecorder({
    required String serverUrl,
    required String deviceId,
  })  : _serverUrl = serverUrl,
        _deviceId = deviceId;

  void updateConfig({String? serverUrl, String? deviceId}) {
    if (serverUrl != null) _serverUrl = serverUrl;
    if (deviceId != null) _deviceId = deviceId;
  }

  bool get isRecording => _isRecording;

  /// Pause sensor subscriptions (app backgrounded).
  void pauseRecording() {
    if (!_isRecording) return;
    _accelSub?.pause();
    _gyroSub?.pause();
    _magSub?.pause();
  }

  /// Resume sensor subscriptions (app foregrounded).
  void resumeRecording() {
    if (!_isRecording) return;
    _accelSub?.resume();
    _gyroSub?.resume();
    _magSub?.resume();
  }

  void startJourney(String stationId, {String? journeyId}) {
    if (_isRecording) return;
    _isRecording = true;
    _currentJourneyId = journeyId ?? _generateId();
    _stationSequence.clear();
    _samples.clear();
    _gpsFixes.clear();
    _stationSequence.add(stationId);
    onRecordingChanged?.call(true);

    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 40),
    ).listen(_onAccelerometer);
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 40),
    ).listen(_onGyroscope);
    _magSub = magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen(_onMagnetometer);
  }

  Future<void> stopJourney({String? endStationId}) async {
    if (!_isRecording) return;
    _isRecording = false;
    onRecordingChanged?.call(false);

    if (endStationId != null) {
      _stationSequence.add(endStationId);
    }

    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _magSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _magSub = null;

    await _uploadTrace();
  }

  // ─── Sensor handlers ───────────────────────────────────────

  void _onAccelerometer(AccelerometerEvent event) {
    if (!_isRecording) return;
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    final magnitude =
        sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    _detectMotion(magnitude, now);

    _samples.add(SensorSample(
      timestamp: now,
      rawAccel: [event.x, event.y, event.z],
      accelerometer: _removeGravity(event.x, event.y, event.z),
      gyroscope: _samples.isNotEmpty ? _samples.last.gyroscope : [0, 0, 0],
      magnetometer: _samples.isNotEmpty ? _samples.last.magnetometer : [0, 0, 0],
      motionClass: _currentMotionClass,
    ));
  }

  void _onGyroscope(GyroscopeEvent event) {
    if (!_isRecording || _samples.isEmpty) return;
    _samples.last.gyroscope = [event.x, event.y, event.z];
  }

  void _onMagnetometer(MagnetometerEvent event) {
    if (!_isRecording || _samples.isEmpty) return;
    _samples.last.magnetometer = [event.x, event.y, event.z];
  }

  // ─── Motion classification ──────────────────────────────────

  void _detectMotion(double magnitude, double now) {
    const double threshold = 1.2;

    if (magnitude > threshold) {
      final delta = now - _lastPeakTime;
      if (delta > 0.2 && delta < 1.2) {
        _peakCount++;
        if (_peakCount > 3) {
          _currentMotionClass = 'walking';
        }
      }
      _lastPeakTime = now;
    } else {
      if (now - _lastPeakTime > 2.0 && _peakCount > 0) {
        _peakCount = 0;
        _currentMotionClass = magnitude < 0.3 ? 'stationary' : 'train';
      }
    }
  }

  /// ponytail: subtract gravity assuming stable device orientation.
  /// Drifts if the phone rotates. Upgrade to gyro-based orientation tracking
  /// when traces show systematic vertical error.
  List<double> _removeGravity(double x, double y, double z) {
    final magnitude = sqrt(x * x + y * y + z * z);
    if (magnitude < 0.01) return [x, y, z];
    final gx = (x / magnitude) * 9.81;
    final gy = (y / magnitude) * 9.81;
    final gz = (z / magnitude) * 9.81;
    return [x - gx, y - gy, z - gz];
  }

  // ─── Upload ─────────────────────────────────────────────────

  Future<void> _uploadTrace() async {
    if (_samples.isEmpty) return;

    // ponytail: downsample to ~10Hz — 25Hz is too much for mobile upload
    final step = (_samples.length ~/ 25).clamp(1, 10);
    final downsampled = <SensorSample>[];
    for (int i = 0; i < _samples.length; i += step) {
      downsampled.add(_samples[i]);
      if (downsampled.length >= 2000) break;
    }

    final trace = TraceUpload(
      traceId: _currentJourneyId ?? _generateId(),
      deviceId: _deviceId,
      networkId: _networkId,
      stationSequence: _stationSequence,
      samples: downsampled,
      gpsFixes: _gpsFixes,
    );

    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/v1/trace'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(trace.toJson()),
      );
      if (response.statusCode == 200) {
        // silent success
      } else {
        // silent fail
      }
    } catch (_) {
      // silent fail
    }
  }

  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
  }

  String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(99999);
    return 'trace-$now-$rand';
  }
}
