# 3D Model Format Specification

## Recommendation: Dual-Format Approach

For v1, use a **custom JSON format** (not glTF). Reasons:
- No dependency on glTF libraries for the server
- Mobile app can parse with `dart:convert` — zero new dependencies
- Backward-compatible with existing GET /api/v1/model endpoint
- glTF adds complexity (binary buffers, accessors, samplers) with no benefit at current scale

Migrate to glTF Binary (.glb) in v2 when:
- The mobile app needs to render hundreds of edges simultaneously
- The model includes textures, materials, or animations
- A WebGL/Flutter 3D library is chosen that natively reads glTF

## Coordinate System

```
WGS84 (lat, lon, elevation) → ENU (meters) → 3D Scene (meters, Y-up)
```

1. Choose an origin station (e.g., "oxford-circus") as ENU reference point
2. Convert all station lat/lon/elevation to ENU meters via geodetic transform
3. Spline points are stored in ENU meters relative to the same origin
4. 3D scene uses Y-up convention

## Spline Representation

For each edge, store **Catmull-Rom control points** (4 per segment):

```json
{
  "edge_id": "euston-warren-street-northern",
  "spline": {
    "type": "catmull-rom",
    "segments": [
      {
        "p0": [0, 0, 0],
        "p1": [50, 2, 0],
        "p2": [150, -1, 0],
        "p3": [200, 0, 0]
      }
    ],
    "tension": 0.5
  }
}
```

For v1, the existing 10-point linear interpolation is fine. Upgrade to Catmull-Rom when the pipeline produces smooth curves.

## Tube Tunnel Geometry

Generate a tube around the spline:

```json
{
  "tunnel": {
    "radius": 1.8,
    "cross_section_segments": 8,
    "closed": true,
    "wall_material": {
      "color": "#2d2d2d",
      "metalness": 0.3,
      "roughness": 0.8
    }
  }
}
```

The mobile app generates the tube mesh at render time from the spline + radius. This keeps the model payload small (no vertex data) and lets the app control LOD.

## LOD Strategy

| LOD | Edges | Spline Points | Tube Segments | Use Case |
|-----|-------|---------------|---------------|----------|
| 0 | All | 10 interpolated | None (line) | Overview / minimap |
| 1 | Visible | 50 interpolated | 8 per segment | Default view |
| 2 | Near | Catmull-Rom control points | 16 per segment | Detail inspection |

Implement LOD selection based on camera distance to the edge or edge length on screen.

## Per-Edge Statistics as Visual Properties

```json
{
  "visualization": {
    "color_by": "speed",
    "speed_range": [5.0, 20.0],
    "color_map": [
      {"value": 5.0, "color": "#ff4444"},
      {"value": 12.0, "color": "#ffaa00"},
      {"value": 20.0, "color": "#44ff44"}
    ],
    "width_by": "trace_count",
    "width_range": [0.5, 3.0]
  }
}
```

The mobile app interpolates colors and widths from the range, using the edge's stats. No server-side mesh generation needed.

## Model Output Structure

```json
{
  "format_version": 2,
  "revision": 147,
  "coordinate_system": "enu",
  "origin": {"lat": 51.5153, "lon": -0.1420, "elevation": 30.0},
  "stations": [
    {"id": "euston", "position": [0, 0, 0], "name": "Euston"}
  ],
  "lines": [
    {"id": "northern", "name": "Northern", "color": "#000000"}
  ],
  "edges": [
    {
      "id": "e1",
      "from": "euston",
      "to": "warren-street",
      "line": "northern",
      "spline": {
        "type": "linear",
        "points": [[0,0,0], [50,2,0], ...]
      },
      "stats": {
        "num_traces": 47,
        "avg_speed_ms": 12.3,
        "mean_accel": [0.3, 0.1, 0.0]
      },
      "tunnel": {"radius": 1.8}
    }
  ],
  "visualization": {
    "color_by": "speed",
    "width_by": "trace_count"
  }
}
```

## Flutter 3D Rendering Options

| Package | Type | Notes |
|---------|------|-------|
| `flutter_cube` | Custom mesh | Simple, no deps, CPU render |
| `flame_3d` | Game engine | Overkill for a map viewer |
| `flutter_gl` | OpenGL wrapper | Requires native interop |
| Custom `CustomPainter` | 2D canvas | **Recommended for v1** — draw splines as lines with varying width/color. Fast, no 3D deps, works on all platforms. |
| `model_viewer_plus` | glTF viewer | For v2 when glTF export is ready |

**Recommendation for v1**: Use `InteractiveViewer` + `CustomPainter` (already implemented in `map_view.dart`). Add tunnel visualization as a 2D projection (edge width represents depth, color represents elevation) rather than true 3D. This gives a useful visualization with zero additional dependencies.
