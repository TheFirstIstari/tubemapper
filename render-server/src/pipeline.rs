use crate::model::{Trace, TubeGraph};

/// Process a single trace: integrate IMU, estimate per-edge spline, update graph.
/// Returns the new model revision.
///
/// ponytail: simple approach — project station-sequence into a path,
/// compute per-edge acceleration statistics, refine spline midpoint.
/// Upgrade to full Kalman smoother + graph SLAM when multi-trace data is available.
pub async fn process_trace(trace: &Trace, graph: &mut TubeGraph) -> u64 {
    graph.total_traces += 1;

    let windows: Vec<(&str, &str)> = trace
        .station_sequence
        .windows(2)
        .map(|w| (w[0].as_str(), w[1].as_str()))
        .collect();

    for (from_id, to_id) in &windows {
        // Find or create edge
        if let Some(edge) = graph.edges.iter_mut().find(|e| {
            (e.from == *from_id && e.to == *to_id)
                || (e.from == *to_id && e.to == *from_id)
        }) {
            edge.num_traces += 1;

            // Classify samples that belong to this edge
            // ponytail: split samples equally among edges in the sequence.
            let samples_per_edge = trace.samples.len() / windows.len().max(1);
            let start = (edge.num_traces as usize).saturating_mul(samples_per_edge)
                / (edge.num_traces as usize + 1).max(1);
            let end = (start + samples_per_edge / (edge.num_traces as usize + 1).max(1))
                .min(trace.samples.len());
            let edge_samples = &trace.samples[start..end];

            for sample in edge_samples {
                *edge
                    .motion_samples
                    .entry(sample.motion_class.clone())
                    .or_insert(0) += 1;
            }

            // Compute average acceleration vector for this edge
            // This tells us the train's acceleration profile between stations
            if !edge_samples.is_empty() {
                let mut avg_accel = [0.0f64; 3];
                for s in edge_samples {
                    for i in 0..3 {
                        avg_accel[i] += s.accelerometer[i];
                    }
                }
                let n = edge_samples.len() as f64;
                for i in 0..3 {
                    avg_accel[i] /= n;
                }

                // Refine spline midpoint based on acceleration direction
                // ponytail: shift the midpoint spline point along the acceleration vector.
                // This very roughly nudges the path toward the actual curve.
                // Real fix: integrate gyro + accel into 6-DOF pose estimate.
                let from_station = graph.stations.iter().find(|s| s.id == *from_id);
                let to_station = graph.stations.iter().find(|s| s.id == *to_id);
                if let (Some(_fs), Some(_ts)) = (from_station, to_station) {
                    if edge.spline_points.len() >= 3 {
                        let mid_idx = edge.spline_points.len() / 2;
                        // Nudge midpoint by acceleration direction (scaled down)
                        // ponytail: _fs and _ts are available for elevation-based refinement
                        let scale = 0.001; // tiny: 1mm per m/s²
                        edge.spline_points[mid_idx][0] += avg_accel[0] * scale;
                        edge.spline_points[mid_idx][1] += avg_accel[1] * scale;
                        edge.spline_points[mid_idx][2] += avg_accel[2] * scale * 10.0; // vertical exaggeration
                    }
                }
            }
        }
    }

    // Bump revision
    graph.revision += 1;
    graph.revision
}
