import 'package:flutter_test/flutter_test.dart';
import 'package:tubemapper_app/services/models.dart';

void main() {
  test('SensorSample serialization round-trip', () {
    final sample = SensorSample(
      timestamp: 123.45,
      accelerometer: [0.1, 9.8, -0.2],
      gyroscope: [0.01, -0.02, 0.0],
      magnetometer: [30.0, -5.0, 42.0],
      rawAccel: [0.1, 9.8, -0.2],
      motionClass: 'train',
    );
    final json = sample.toJson();
    expect(json['timestamp'], 123.45);
    expect(json['motion_class'], 'train');
  });

  test('TraceUpload builds valid JSON', () {
    final upload = TraceUpload(
      traceId: 'test-1',
      deviceId: 'device-1',
      networkId: 'london-underground',
      stationSequence: ['oxford-circus', 'tottenham-court-road'],
      samples: [],
      gpsFixes: [],
    );
    final json = upload.toJson();
    expect(json['trace_id'], 'test-1');
    expect(json['station_sequence'], hasLength(2));
  });
}
