# 3D Model Format Specification for Tube Map Viewer

## Overview
This document specifies the output format for 3D rendering of tube/subway maps. The format evolves from the existing JSON structure to support 3D visualization while maintaining compatibility with 2D use cases.

## Recommended Format: glTF 2.0
We recommend using **glTF 2.0** (Binary GLB) as the primary 3D model format because:
- Industry standard for 3D web and mobile applications
- Efficient binary format with JSON metadata
- Supports PBR materials, animations, and extensions
- Well-supported in Flutter via `model_viewer_plus` and `flutter_gltf`
- Allows embedding of multiple scenes (LODs) in a single file

Alternative: Custom JSON format for simple prototypes, but glTF is preferred for production.

## Coordinate System Transformation
1. **WGS84** (input): Latitude, longitude, elevation (meters above sea level)
2. **Local ENU** (East-North-Up): Tangent plane projection centered at map origin
   - Origin: Arbitrary reference point (e.g., first station or map center)
   - Conversion: Use geodetic to ENU formulas (e.g., via GeographicLib or PROJ)
3. **3D Scene Coordinates**: Right-handed system (X=East, Y=Up, Z=North) with Y up for compatibility with most 3D engines

## Data Structure
The glTF file contains:
- **Buffer**: Binary geometry data (vertices, normals, UVs, indices)
- **BufferViews**: Slices into the buffer for different attributes
- **Accessors**: Typed access to bufferView data
- **Materials**: PBR materials for visual encoding
- **Meshes**: Tube geometries and station markers
- **Nodes**: Scene hierarchy (optional grouping by line)
- **Scene**: Root scene containing all nodes

### Per-Edge Geometry Representation
Each edge (track segment between stations) is represented as:
1. **Spline Curve**: Cubic Hermite spline defined by:
   - Start/end points (WGS84 converted to ENU)
   - Start/end tangents (derived from adjacent edges for C1 continuity)
   - Stored as: 4 control points per segment (p0, p1, p2, p3) in ENU space
2. **Tube Geometry**: Extruded circular profile along spline:
   - Radius: Constant (e.g., 1.5 meters) or variable based on line/traffic
   - Tessellation: Configurable (default 16 segments around circumference)
   - Spline sampling: Adaptive based on curvature (more points where curvature high)

### Spline Storage in glTF
Option A (Recommended): Store as mesh with vertices/tangents:
- Vertex attribute: `POSITION` (spline control points)
- Vertex attribute: `TANGENT` (outgoing tangent vector)
- Vertex attribute: `NORMAL` (incoming tangent vector)
- Material properties encoded via vertex colors or texture coordinates

Option B: Store spline as accessor data and generate tube in shader (requires custom extension).

### Visual Encoding of Statistics
Per-edge statistics mapped to visual properties:
- **Average Speed**: Color gradient (blue=slow, red=fast) via material baseColor
- **Trace Count**: Tube radius or extrusion scale (more traces = thicker tube)
- **Acceleration**: Emissive intensity or pattern (optional)

Implementation: Use vertex colors or material properties:
- Vertex color: RGB = speed encoding, A = trace count normalized
- Or: Material metallic/roughness for speed, emissive for acceleration

## Level of Detail (LOD) Strategy
For mobile rendering, implement multiple LODs:
1. **High Detail**: Full tube mesh with 16-32 radial segments, spline sampled every 2m
2. **Medium Detail**: 8-12 radial segments, spline sampled every 5m
3. **Low Detail**: 4-6 radial segments, spline sampled every 10m, or replaced by line strips
4. **Impostor**: For distant edges, use billboarded quad with pre-rendered render

LOD selection based on:
- Distance from camera
- Screen space error metric
- Frustum culling

Store multiple mesh primitives per edge under different primitives with varying attributes.

## Station Representation
Stations as:
- **Geometry**: Sphere or rounded cube (radius 2-3m)
- **Properties**: 
  - Color: Line color(s) of connecting edges (blended if multiple lines)
  - Emissive: Passenger volume (optional)
  - Label: Billboarded text or texture atlas

## File Structure Example
```
tube_map.glb
├─ scene (RootNode)
│  ├─ Line_0_Group (Node)
│  │  ├─ Edge_0_Mesh (MeshPrimitive)
│  │  │  ├─ attributes: POSITION, NORMAL, TANGENT, COLOR_0
│  │  │  ├─ material: EdgeMaterial
│  │  │  ├─ mode: TRIANGLES
│  │  │  └─ targets: [LOD1_mesh, LOD2_mesh] (optional)
│  │  └─ Edge_1_Mesh ...
│  ├─ Line_1_Group ...
│  └─ Stations_Group
│     ├─ Station_0_Mesh (sphere)
│     └─ Station_1_Mesh ...
├─ materials
│  ├─ EdgeMaterial (PBR metallicRoughness)
│  │  ├─ baseColorFactor: [0.2, 0.6, 0.8, 1.0] (speed-based)
│  │  ├─ metallicFactor: 0.0
│  │  ├─ roughnessFactor: 0.9
│  │  └─ emissiveFactor: [accel_r, accel_g, accel_b]
│  └─ StationMaterial
└─ accessors and buffers for geometry data
```

## Recommended Flutter Packages
1. **`model_viewer_plus`**: Easy glTF viewing with AR support
   - Dependencies: `model_viewer_plus: ^3.0.0`
   - Features: Camera controls, background, AR mode
2. **`flutter_gltf`**: Lower-level glTF parsing for custom rendering
   - Use when needing direct access to mesh data or custom shaders
3. **`vector_math`**: For ENU/WGS84 conversion math
4. **`flutter_riverpod` or `provider`**: For state management of LOD selection

## Implementation Notes
- **Coordinate Precision**: Use single-precision float (glTF default) - sufficient for city-scale maps with ENU origin
- **File Size Optimization**: 
  - Draco mesh compression extension
  - Quantize vertex attributes where possible (positions to 16-bit)
  - BasisU compression for textures (if using texture-based labels)
- **Streaming**: For large cities, consider splitting by geographic tiles with separate glTF files
- **Animation**: Optional: train movement along splines using glTF animations or custom vertex shader

## Backward Compatibility
The 3D format can coexist with existing 2D JSON:
- Same station/line/edge IDs
- Additional fields for 3D can be ignored by 2D clients
- Conversion utility: Generate both formats from common internal representation

## Example snplien representation in ENU (meters)
```
Edge {
  id: "e1",
  line: "red",
  spline_control_points: [  // 4 points per cubic segment
    [x0, y0, z0],  // p0 (start)
    [x1, y1, z1],  // p1 (start tangent)
    [x2, y2, z2],  // p2 (end tangent)
    [x3, y3, z3]   // p3 (end)
  ],
  radius: 1.8,
  stats: {
    avg_speed_ms: 12.5,
    trace_count: 150,
    mean_accel: 0.3
  }
}
```

## Next Steps
1. Implement WGS84 to ENU conversion in data pipeline
2. Generate spline control points from existing lat/lon/elevation points
3. Export to glTF using `dart_gltf` or `gltf` package
4. Test rendering test dataset