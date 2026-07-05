import 'package:flutter/material.dart';
import '../services/models.dart';

/// A simple 2D map view of the tube network.
/// ponytail: CustomPainter + InteractiveViewer. 
/// Upgrade to WebGL / 3D when the spline data is rich enough.
class MapViewer extends StatelessWidget {
  final List<Station> stations;
  final Map<String, Color> lineColors;
  final List<List<Map<String, dynamic>>> edgesByLine;

  const MapViewer({
    super.key,
    required this.stations,
    required this.lineColors,
    required this.edgesByLine,
  });

  @override
  Widget build(BuildContext context) {
    if (stations.isEmpty) {
      return const Center(child: Text('No station data'));
    }

    // Compute bounds
    double minLat = stations.map((s) => s.lat).reduce(min);
    double maxLat = stations.map((s) => s.lat).reduce(max);
    double minLon = stations.map((s) => s.lon).reduce(min);
    double maxLon = stations.map((s) => s.lon).reduce(max);

    // Add padding
    final padLat = (maxLat - minLat) * 0.05;
    final padLon = (maxLon - minLon) * 0.05;
    minLat -= padLat;
    maxLat += padLat;
    minLon -= padLon;
    maxLon += padLon;

    return InteractiveViewer(
      minScale: 0.3,
      maxScale: 5.0,
      constrained: false,
      child: SizedBox(
        width: 1200,
        height: 1600,
        child: CustomPaint(
          painter: _MapPainter(
            stations: stations,
            edgesByLine: edgesByLine,
            lineColors: lineColors,
            minLat: minLat,
            maxLat: maxLat,
            minLon: minLon,
            maxLon: maxLon,
          ),
        ),
      ),
    );
  }
}

double min(double a, double b) => a < b ? a : b;
double max(double a, double b) => a > b ? a : b;

class _MapPainter extends CustomPainter {
  final List<Station> stations;
  final List<List<Map<String, dynamic>>> edgesByLine;
  final Map<String, Color> lineColors;
  final double minLat, maxLat, minLon, maxLon;

  _MapPainter({
    required this.stations,
    required this.edgesByLine,
    required this.lineColors,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  Offset _project(double lat, double lon, Size size) {
    final x = (lon - minLon) / (maxLon - minLon) * size.width;
    final y = (maxLat - lat) / (maxLat - minLat) * size.height;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFF5F5F5),
    );

    // Draw edges
    for (final lineEdges in edgesByLine) {
      for (final edge in lineEdges) {
        final from = stations.firstWhere(
          (s) => s.id == edge['from'],
          orElse: () => stations.first,
        );
        final to = stations.firstWhere(
          (s) => s.id == edge['to'],
          orElse: () => stations.first,
        );
        final color = lineColors[edge['line']] ?? Colors.grey;

        final linePaint = Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke;

        canvas.drawLine(
          _project(from.lat, from.lon, size),
          _project(to.lat, to.lon, size),
          linePaint,
        );
      }
    }

    // Draw stations
    final stationPaint = Paint()..color = Colors.black87;
    final labelPaint = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (final s in stations) {
      final pos = _project(s.lat, s.lon, size);
      canvas.drawCircle(pos, 4, stationPaint);

      // Label every Nth station to avoid clutter
      // ponytail: skip labels for dense clusters
      labelPaint.text = TextSpan(
        text: s.name,
        style: const TextStyle(fontSize: 8, color: Colors.black54),
      );
      labelPaint.layout();
      labelPaint.paint(canvas, pos + const Offset(6, -4));
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}
