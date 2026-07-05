import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Server connection settings.
/// ponytail: plain old stateful widget with TextEditingController.
/// Add persistent storage (shared_preferences) when the user's tired of re-entering.
class SettingsScreen extends StatefulWidget {
  final String currentUrl;
  final String currentDeviceId;
  final ValueChanged<String> onUrlChanged;
  final ValueChanged<String> onDeviceIdChanged;

  const SettingsScreen({
    super.key,
    required this.currentUrl,
    required this.currentDeviceId,
    required this.onUrlChanged,
    required this.onDeviceIdChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlCtrl;
  late TextEditingController _deviceCtrl;
  String _testResult = '';
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.currentUrl);
    _deviceCtrl = TextEditingController(text: widget.currentDeviceId);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _deviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = '';
    });

    try {
      final resp = await http
          .get(Uri.parse('${_urlCtrl.text}/api/v1/status'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _testResult =
            '✓ Connected — ${data['network_name']}, r${data['model_revision']}, ${data['total_traces']} traces');
      } else {
        setState(() => _testResult = '✗ Server returned ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _testResult = '✗ Connection failed: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Server URL',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              hintText: 'http://localhost:3000',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() => _testResult = ''),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find, size: 18),
                label: Text(_testing ? 'Testing...' : 'Test Connection'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  widget.onUrlChanged(_urlCtrl.text);
                  widget.onDeviceIdChanged(_deviceCtrl.text);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Settings saved'),
                        duration: Duration(seconds: 1)),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
          if (_testResult.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_testResult,
                style: TextStyle(
                  color: _testResult.startsWith('✓')
                      ? Colors.green
                      : Colors.red,
                )),
          ],
          const SizedBox(height: 24),
          Text('Device ID',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _deviceCtrl,
            decoration: const InputDecoration(
              hintText: 'device-xxx',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 24),
          Text('Network',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green, size: 20),
            title: Text('London Underground'),
            subtitle: Text('279 stations, 362 edges'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          Text('API Endpoints',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _endpoint('GET  /api/v1/status', 'Server health & stats'),
          _endpoint('POST /api/v1/trace', 'Upload sensor trace'),
          _endpoint('GET  /api/v1/model', 'Download current 3D model'),
          _endpoint('GET  /api/v1/network', 'Network definition'),
          _endpoint('POST /api/v1/workers/register', 'Worker registration'),
          _endpoint('POST /api/v1/workers/heartbeat', 'Worker heartbeat'),
        ],
      ),
    );
  }

  Widget _endpoint(String path, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(path,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: Colors.black87)),
          const SizedBox(width: 8),
          Text(desc,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }
}
