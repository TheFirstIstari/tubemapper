import 'package:flutter/material.dart';
import 'services/sensor_recorder.dart';
import 'services/geofence_trigger.dart';
import 'services/api_client.dart';
import 'services/models.dart';
import 'screens/map_view.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TubeMapperApp());
}

class TubeMapperApp extends StatelessWidget {
  const TubeMapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TubeMapper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003688),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _serverUrl = 'http://localhost:3000';
  String _deviceId = 'device-${DateTime.now().millisecondsSinceEpoch}';

  late final ApiClient _api;
  late final SensorRecorder _recorder;
  late final GeofenceTrigger _geofence;

  List<Station> _stations = [];
  ServerStatus? _status;
  bool _loading = true;
  int _selectedTab = 0;

  // Model data for map viewer
  final Map<String, Color> _lineColors = {};
  List<List<Map<String, dynamic>>> _edgesByLine = [];

  @override
  void initState() {
    super.initState();
    _api = ApiClient(_serverUrl);
    _recorder = SensorRecorder(
      serverUrl: _serverUrl,
      deviceId: _deviceId,
    );
    // Create placeholder geofence, real one is created in _init after stations load
    _geofence = GeofenceTrigger(_recorder, []);
    _init();
  }

  Future<void> _init() async {
    final stations = await _api.loadLocalNetwork();
    final status = await _api.getStatus();

    // Dispose placeholder geofence, create real one with stations
    _geofence.dispose();
    _geofence = GeofenceTrigger(_recorder, stations);

    setState(() {
      _stations = stations;
      _status = status;
      _loading = false;
    });

    // Build line colors map
    if (stations.isNotEmpty) {
      _buildLineColors();
    }

    // Fetch model from server
    if (status != null) {
      await _fetchModel();
    }
  }

  void _buildLineColors() {
    const defaults = {
      'bakerloo': Color(0xFFB36305),
      'central': Color(0xFFE32017),
      'circle': Color(0xFFFFD300),
      'district': Color(0xFF007229),
      'hammersmith-city': Color(0xFFF3A9BB),
      'jubilee': Color(0xFFA0A5D9),
      'metropolitan': Color(0xFF9B0056),
      'northern': Color(0xFF000000),
      'piccadilly': Color(0xFF003688),
      'victoria': Color(0xFF0098D8),
      'waterloo-city': Color(0xFF95CDBA),
    };
    _lineColors.addAll(defaults);
  }

  Future<void> _fetchModel() async {
    final model = await _api.getModel();
    if (model == null) return;

    final linesRaw = model['lines'] as List?;
    if (linesRaw != null) {
      for (final l in linesRaw) {
        final colorStr = l['color'] as String?;
        if (colorStr != null) {
          final c = _parseHexColor(colorStr);
          _lineColors[l['id']] = c;
        }
      }
    }

    // Group edges by line
    final edgesRaw = (model['edges'] as List?) ?? [];
    final byLine = <String, List<Map<String, dynamic>>>{};
    for (final e in edgesRaw) {
      final line = e['line'] as String? ?? '';
      byLine.putIfAbsent(line, () => []).add(e as Map<String, dynamic>);
    }
    setState(() {
      _edgesByLine = byLine.values.toList();
    });
  }

  Color _parseHexColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  @override
  void dispose() {
    _recorder.dispose();
    _geofence.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final status = await _api.getStatus();
    setState(() => _status = status);
    if (status != null) await _fetchModel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TubeMapper'),
        actions: [
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text('r${_status!.modelRevision}'),
                avatar: const Icon(Icons.model_training, size: 16),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _selectedTab,
              children: [
                _buildRecordTab(),
                _buildMapTab(),
                SettingsScreen(
                  currentUrl: _serverUrl,
                  currentDeviceId: _deviceId,
                  onUrlChanged: (url) {
                    setState(() => _serverUrl = url);
                    _api.updateUrl(url);
                    _recorder.updateConfig(serverUrl: url);
                  },
                  onDeviceIdChanged: (id) {
                    setState(() => _deviceId = id);
                    _recorder.updateConfig(deviceId: id);
                  },
                ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (i) => setState(() => _selectedTab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fiber_manual_record),
            selectedIcon: Icon(Icons.fiber_manual_record, color: Colors.red),
            label: 'Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTab() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(),
          const SizedBox(height: 16),
          _buildControlsCard(),
          const SizedBox(height: 16),
          _buildStationList(),
        ],
      ),
    );
  }

  Widget _buildMapTab() {
    if (_edgesByLine.isEmpty) {
      return const Center(child: Text('No model data — connect to server first'));
    }
    return MapViewer(
      stations: _stations,
      lineColors: _lineColors,
      edgesByLine: _edgesByLine,
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_status != null) ...[
              _row('Network', _status!.networkName),
              _row('Traces', '${_status!.totalTraces}'),
              _row('Revision', '${_status!.modelRevision}'),
              _row('Stations', '${_status!.stations}'),
              _row('Edges', '${_status!.edges}'),
              if (_status!.workers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Workers', style: Theme.of(context).textTheme.titleSmall),
                ...(_status!.workers.map((w) =>
                    _row('${w.url}', 'r${w.modelRevision}'))),
              ],
            ] else
              const Text('Offline — start server and pull to refresh'),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard() {
    final recording = _recorder.isRecording;
    final monitoring = _geofence.isMonitoring;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recorder', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  recording ? Icons.fiber_manual_record : Icons.stop_circle,
                  color: recording ? Colors.red : Colors.grey,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recording ? 'Recording' : 'Idle'),
                    Text(
                      monitoring ? 'Geo-monitoring active' : 'Geo off',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!recording) ...[
                  FilledButton.icon(
                    onPressed: () => _recorder.startJourney('manual'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Manual'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _geofence.start(),
                    icon: const Icon(Icons.location_on),
                    label: const Text('Auto-Detect'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () => _recorder.stopJourney(),
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stations (${_stations.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._stations.take(20).map(
                  (s) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.circle, size: 12),
                    title: Text(s.name),
                    subtitle: Text('${s.lat.toStringAsFixed(4)}, ${s.lon.toStringAsFixed(4)}'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            if (_stations.length > 20)
              Text('... and ${_stations.length - 20} more',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
