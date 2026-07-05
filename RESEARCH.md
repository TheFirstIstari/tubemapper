# IMU Fusion Research for 3D Rail Reconstruction

## Problem Statement
Reconstruct a 3D rail tunnel geometry from phone accelerometer + gyroscope data, using known station positions (anchor points) to bound drift.

## Strapdown Inertial Navigation (Dead Reckoning)

Between known station anchors, the phone's IMU is integrated to estimate position:

1. **Gyroscope** → orientation (quaternion or rotation matrix)
   - Integrate angular velocity to get attitude
   - Drift: ~1°/min for phone-grade MEMS gyros
   
2. **Accelerometer** → velocity → position (double integration)
   - Rotate raw acceleration from body frame to world frame using the gyro-derived orientation
   - Subtract gravity vector (known from accelerometer when stationary)
   - Integrate to velocity, integrate again to position
   - Drift: position error grows as t² (time squared) — catastrophic within seconds

3. **Drift sources**:
   - Gyro bias → orientation drift → gravity vector misalignment → wrong acceleration
   - Accelerometer bias → velocity ramp error
   - Sensor noise → random walk (grows as √t)
   - Non-gravity forces (phone vibration, pocket bouncing)

## Station Anchors as Correction Points

Tube stations provide known 3D positions (lat, lon, elevation). These correct drift:

- At station entry: position is reset to known coordinates
- Between stations: integrate IMU, drift accumulates
- At next station: compute error = (integrated position - known position)
- This error constrains the tunnel shape between the two stations

With multiple phone traces over the same edge, the error distribution converges to the true tunnel geometry.

## Sensor Fusion Approaches

### 1. Complementary Filter (Lazy — recommended for v1)
Fuses gyro orientation (high-frequency, drifts) with accelerometer gravity vector (low-frequency, noisy):

```
orientation = α * (orientation + gyro * dt) + (1-α) * accel_gravity_estimate
```

- Pros: Simple, no state vector, no covariance, single tunable parameter
- Cons: No formal uncertainty model, ad-hoc tuning
- **Recommendation for v1**: Works well for phone orientation. The station anchor correction replaces the need for a full Kalman filter.

### 2. Extended Kalman Filter (Standard approach)
State vector: [position, velocity, orientation (quaternion), gyro_bias, accel_bias]
- Predict: IMU integration step
- Update: Station position fix, zero-velocity updates (stationary at platform)
- Pros: Formal uncertainty propagation, proven in navigation
- Cons: Tuning Q/R matrices is non-trivial, sensitive to initialization

### 3. Factor Graph Optimization (Best quality, most complex)
Build a graph of IMU pre-integration factors between station nodes. Solve via nonlinear least squares (like SLAM).
- Pros: Handles arbitrary numbers of traces, naturally fuses multiple passes over same edge, batch optimization
- Cons: Requires library (GTSAM or similar), heavier compute than filter
- **Recommendation for v2**: Once enough traces exist, this will produce the best 3D model

## Coordinate Frame Transformations

```
Phone Body Frame → World Frame → Local ENU → Tunnel-Aligned Frame
```

1. **Body → World**: Rotation matrix from gyro-integrated quaternion
2. **World → ENU**: Geodetic transform (WGS84 latitude/longitude → East-North-Up tangent plane)
3. **ENU → Tunnel**: Optional rotation to align tunnel axis with X-axis for easier visualization

## Rust Implementation Recommendations

### v1 (Current pipeline)
```
For each edge in trace.station_sequence:
  - Compute mean acceleration (world frame, gravity removed)
  - Use mean accel direction to nudge spline control points
  - Average speed from dwell time = (last.timestamp - first.timestamp) / edge.length_m
```
This is what the current pipeline does. The nudge is uniform and small.

### v2 (Strapdown + Complementary)
```
For each sample block assigned to an edge:
  - Integrate gyro Z → yaw angle
  - Rotate accel by yaw to approximate world frame
  - Subtract gravity [0, 0, 9.81] assuming pitch/roll negligible
  - Double integrate to displacement
  - Compare displacement to known chord (endpoints)
  - Distribute residual error along the edge (spline displacement)
```

### v3 (Kalman smoother)
```
For each edge:
  - Run forward EKF: IMU predict, station anchor update
  - Run backward smoother (Rauch-Tung-Striebel)
  - Extract MAP trajectory estimate
  - Convert trajectory to spline control points
```

## Recommended Rust Crates

| Crate | Use | v? |
|-------|-----|----|
| `nalgebra` | Vectors, matrices, quaternions | v1+ |
| `quaternion` | Lightweight quaternion operations | v1 |
| `imu_fusion` | Complementary filter implemention | v2 |
| `gtsam` (ffi) | Factor graph optimization | v3 |
| `approx` | Floating-point comparison in tests | v1+ |

## Recommendation
Start with **v2 strapdown integration** using gyro yaw + accel double-integration between station anchors. The complementary filter for orientation is overkill when station anchors exist every 1-2km — the drift never accumulates enough to matter. Upgrade to factor graph optimization once 100+ traces per edge exist.
