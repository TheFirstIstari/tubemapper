import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'models.dart';

/// Exception thrown by ApiClient on HTTP or network errors.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message${statusCode != null ? ' ($statusCode)' : ''}';
}

/// Communicates with the tube-mapper render server.
class ApiClient {
  String _baseUrl;

  ApiClient(this._baseUrl);

  void updateUrl(String url) {
    _baseUrl = url;
  }

  /// Fetch network definition (stations, edges, lines).
  /// ponytail: for v1, load from bundled JSON. Switch to server fetch when
  /// we support multiple networks downloadable from the server.
  Future<List<Station>> loadLocalNetwork() async {
    final jsonStr =
        await rootBundle.loadString('assets/london-underground.json');
    final data = jsonDecode(jsonStr);
    final stations = (data['stations'] as List)
        .map((s) => Station.fromJson(s))
        .toList();
    return stations;
  }

  /// Get server status.
  Future<ServerStatus?> getStatus() async {
    try {
      final resp = await http.get(Uri.parse('$_baseUrl/api/v1/status'));
      if (resp.statusCode == 200) {
        return ServerStatus.fromJson(jsonDecode(resp.body));
      }
    } catch (_) {}
    return null;
  }

  /// Get current model.
  Future<Map<String, dynamic>?> getModel() async {
    try {
      final resp = await http.get(Uri.parse('$_baseUrl/api/v1/model'));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body);
      }
    } catch (_) {}
    return null;
  }
}
