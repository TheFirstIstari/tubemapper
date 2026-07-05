class SensorSample {
  double timestamp;
  List<double> accelerometer;
  List<double> gyroscope;
  List<double> magnetometer;
  List<double> rawAccel;
  String motionClass;

  SensorSample({
    required this.timestamp,
    required this.accelerometer,
    required this.gyroscope,
    required this.magnetometer,
    required this.rawAccel,
    this.motionClass = 'unknown',
  });

  SensorSample copyWith({
    double? timestamp,
    List<double>? accelerometer,
    List<double>? gyroscope,
    List<double>? magnetometer,
    List<double>? rawAccel,
    String? motionClass,
  }) {
    return SensorSample(
      timestamp: timestamp ?? this.timestamp,
      accelerometer: accelerometer ?? this.accelerometer,
      gyroscope: gyroscope ?? this.gyroscope,
      magnetometer: magnetometer ?? this.magnetometer,
      rawAccel: rawAccel ?? this.rawAccel,
      motionClass: motionClass ?? this.motionClass,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'accelerometer': accelerometer,
        'gyroscope': gyroscope,
        'magnetometer': magnetometer,
        'raw_accel': rawAccel,
        'motion_class': motionClass,
      };
}

class GpsFix {
  final double timestamp;
  final double lat;
  final double lon;
  final double accuracyM;
  final double elevationM;

  GpsFix({
    required this.timestamp,
    required this.lat,
    required this.lon,
    this.accuracyM = 0,
    this.elevationM = 0,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'lat': lat,
        'lon': lon,
        'accuracy_m': accuracyM,
        'elevation_m': elevationM,
      };
}

class TraceUpload {
  final String traceId;
  final String deviceId;
  final String networkId;
  final List<String> stationSequence;
  final List<SensorSample> samples;
  final List<GpsFix> gpsFixes;

  TraceUpload({
    required this.traceId,
    required this.deviceId,
    required this.networkId,
    required this.stationSequence,
    required this.samples,
    required this.gpsFixes,
  });

  Map<String, dynamic> toJson() => {
        'trace_id': traceId,
        'device_id': deviceId,
        'network_id': networkId,
        'station_sequence': stationSequence,
        'samples': samples.map((s) => s.toJson()).toList(),
        'gps_fixes': gpsFixes.map((g) => g.toJson()).toList(),
      };
}

class ServerStatus {
  final String networkId;
  final String networkName;
  final int modelRevision;
  final int totalTraces;
  final int stations;
  final int edges;
  final List<WorkerInfo> workers;

  ServerStatus({
    required this.networkId,
    required this.networkName,
    required this.modelRevision,
    required this.totalTraces,
    required this.stations,
    required this.edges,
    this.workers = const [],
  });

  factory ServerStatus.fromJson(Map<String, dynamic> json) => ServerStatus(
        networkId: json['network_id'],
        networkName: json['network_name'],
        modelRevision: json['model_revision'],
        totalTraces: json['total_traces'],
        stations: json['stations'],
        edges: json['edges'],
        workers: (json['workers'] as List?)
                ?.map((w) => WorkerInfo.fromJson(w))
                .toList() ??
            [],
      );
}

class WorkerInfo {
  final String url;
  final String status;
  final double load;
  final int modelRevision;

  WorkerInfo({
    required this.url,
    required this.status,
    required this.load,
    required this.modelRevision,
  });

  factory WorkerInfo.fromJson(Map<String, dynamic> json) => WorkerInfo(
        url: json['url'],
        status: json['status'],
        load: (json['load'] as num).toDouble(),
        modelRevision: json['model_revision'],
      );
}

class Station {
  final String id;
  final String name;
  final double lat;
  final double lon;

  Station({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
  });

  factory Station.fromJson(Map<String, dynamic> json) => Station(
        id: json['id'],
        name: json['name'],
        lat: json['lat'],
        lon: json['lon'],
      );
}
