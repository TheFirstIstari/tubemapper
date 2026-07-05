use crate::model::{Trace, TubeGraph};

/// Process a single trace: assign samples to edges by contiguous blocks,
/// compute dwell time, accumulate IMU data, refine spline.
/// Returns the new model revision.
pub async fn process_trace(trace: &Trace, graph: &mut TubeGraph) -> u64 {
    graph.total_traces += 1;

    let windows: Vec<(&str, &str)> = trace
        .station_sequence
        .windows(2)
        .map(|w| (w[0].as_str(), w[1].as_str()))
        .collect();

    if windows.is_empty() || trace.samples.is_empty() {
        graph.revision += 1;
        return graph.revision;
    }

    // Assign contiguous sample blocks to edges
    let block_size = trace.samples.len() / windows.len();
    for (i, (from_id, to_id)) in windows.iter().enumerate() {
        let start = i * block_size;
        let end = if i == windows.len() - 1 {
            trace.samples.len()
        } else {
            start + block_size
        };
        let edge_samples = &trace.samples[start..end.min(trace.samples.len())];

        if let Some(edge) = graph.edges.iter_mut().find(|e| {
            (e.from == *from_id && e.to == *to_id)
                || (e.from == *to_id && e.to == *from_id)
        }) {
            edge.num_traces += 1;

            // Motion class counts
            for sample in edge_samples {
                *edge
                    .motion_samples
                    .entry(sample.motion_class.clone())
                    .or_insert(0) += 1;
            }

            // Dwell time from first→last timestamp on this edge
            let dwell_s = if edge_samples.len() >= 2 {
                (edge_samples.last().unwrap().timestamp
                    - edge_samples.first().unwrap().timestamp)
                    .abs()
            } else {
                1.0
            };
            edge.avg_speed_ms = if dwell_s > 0.0 && edge.length_m > 0 {
                Some(edge.length_m as f64 / dwell_s)
            } else {
                None
            };

            // Accumulate acceleration in world frame (yaw-corrected)
            // ponytail: integrate gyro z-axis for heading, rotate accel by heading.
            // Full 6-DOF fusion (pitch/roll from gravity vector) is deferred.
            let mut cumul_heading = 0.0;
            let mut world_accels: Vec<[f64; 3]> = Vec::with_capacity(edge_samples.len());

            for s in edge_samples {
                cumul_heading += s.gyroscope[2] * 0.04; // 40ms sample period
                let (sin_h, cos_h) = cumul_heading.sin_cos();
                // Rotate accel by heading (z-axis rotation)
                let wx = s.accelerometer[0] * cos_h - s.accelerometer[1] * sin_h;
                let wy = s.accelerometer[0] * sin_h + s.accelerometer[1] * cos_h;
                world_accels.push([wx, wy, s.accelerometer[2]]);
            }

            // Compute mean world-frame acceleration for this trace on this edge
            let mean_accel = if !world_accels.is_empty() {
                let n = world_accels.len() as f64;
                let sum: [f64; 3] = world_accels
                    .iter()
                    .fold([0.0, 0.0, 0.0], |acc, v| {
                        [acc[0] + v[0], acc[1] + v[1], acc[2] + v[2]]
                    });
                [sum[0] / n, sum[1] / n, sum[2] / n]
            } else {
                [0.0, 0.0, 0.0]
            };

            // Refine spline: displace interior points by mean acceleration
            // ponytail: uniform displacement, upgrade to per-segment when heading stabilizes.
            const DISPLACEMENT_SCALE: f64 = 0.01;
            let interior_count = edge.spline_points.len().saturating_sub(2);
            for pt in edge.spline_points.iter_mut().skip(1).take(interior_count) {
                pt[0] += mean_accel[0] * DISPLACEMENT_SCALE;
                pt[1] += mean_accel[1] * DISPLACEMENT_SCALE;
                pt[2] += mean_accel[2] * DISPLACEMENT_SCALE * 5.0; // vertical exaggeration
            }

            // Store mean accel for this trace on edge stats
            edge.mean_accel = mean_accel;
        }
    }

    graph.revision += 1;
    graph.revision
}
