use crate::model::{Trace, TubeGraph};

/// Process a trace: assign samples to edges by contiguous blocks,
/// compute dwell time, accumulate IMU data, refine spline.
/// Returns the new model revision number.
/// Returns None if the trace cannot be processed (empty sequence, unknown stations).
pub fn process_trace(trace: &Trace, graph: &mut TubeGraph) -> Option<u64> {
    if trace.station_sequence.len() < 2 {
        return None;
    }

    // Validate all stations exist in the graph
    for sid in &trace.station_sequence {
        if !graph.stations.iter().any(|s| s.id == *sid) {
            return None;
        }
    }

    let samples_per_window = trace.samples.len() / trace.station_sequence.len().max(1);

    // Window-based edge matching: triples of stations → 2 edges
    let windows: Vec<&[String]> = trace.station_sequence.windows(3).collect();
    if windows.is_empty() {
        // Only 2 stations → single edge
        let from = &trace.station_sequence[0];
        let to = &trace.station_sequence[1];
        let edge_id = format!("{}-{}", from, to);

        if let Some(edge) = graph.edges.iter_mut().find(|e| e.id == edge_id) {
            edge.num_traces += 1;
            process_samples_for_edge(trace, edge, 0, trace.samples.len());
        }
        return Some(graph.revision + 1);
    }

    for (i, win) in windows.iter().enumerate() {
        let from = &win[0];
        let to = &win[2];
        let edge_id = format!("{}-{}", from, to);

        // Assign samples to this edge
        let start = i * samples_per_window;
        let end = if i == windows.len() - 1 {
            trace.samples.len()
        } else {
            (i + 1) * samples_per_window
        };

        if start >= trace.samples.len() {
            break;
        }

        if let Some(edge) = graph.edges.iter_mut().find(|e| e.id == edge_id) {
            edge.num_traces += 1;
            process_samples_for_edge(trace, edge, start, end);
        }
    }

    Some(graph.revision + 1)
}

fn process_samples_for_edge(trace: &Trace, edge: &mut crate::model::Edge, start: usize, end: usize) {
    let samples = &trace.samples[start..end.min(trace.samples.len())];
    if samples.is_empty() {
        return;
    }

    // Compute yaw from integrated gyro z-axis
    let mut yaw: f64 = 0.0;
    for s in samples {
        yaw += s.gyroscope[2] * 0.02; // assume 50Hz sample rate
    }

    let (sin_yaw, cos_yaw) = yaw.sin_cos();

    // Rotate mean acceleration to world frame (in-plane only)
    let mut sum_world = [0.0f64; 3];
    for s in samples {
        let bx = s.accelerometer[0];
        let by = s.accelerometer[1];
        // Rotate body x,y by yaw
        let wx = bx * cos_yaw - by * sin_yaw;
        let wy = bx * sin_yaw + by * cos_yaw;
        sum_world[0] += wx;
        sum_world[1] += wy;
        sum_world[2] += s.accelerometer[2]; // z remains body-frame
    }
    if !samples.is_empty() {
        let n = samples.len() as f64;
        let world_mean = [sum_world[0] / n, sum_world[1] / n, sum_world[2] / n];

        // Count motion classes
        for s in samples {
            *edge.motion_samples.entry(s.motion_class.clone()).or_insert(0) += 1;
        }

        // Compute avg speed from dwell time
        if let (Some(first), Some(last)) = (samples.first(), samples.last()) {
            let dwell = (last.timestamp - first.timestamp).abs();
            if dwell > 0.001 && edge.length_m > 0 {
                let speed = edge.length_m as f64 / dwell;
                edge.avg_speed_ms = match edge.avg_speed_ms {
                    Some(prev) => Some((prev * (edge.num_traces - 1) as f64 + speed) / edge.num_traces as f64),
                    None => Some(speed),
                };
            }
        }

        // Update running mean acceleration
        let prev_count = edge.num_traces.saturating_sub(1) as f64;
        if prev_count > 0.0 {
            edge.mean_accel = [
                (edge.mean_accel[0] * prev_count + world_mean[0]) / edge.num_traces as f64,
                (edge.mean_accel[1] * prev_count + world_mean[1]) / edge.num_traces as f64,
                (edge.mean_accel[2] * prev_count + world_mean[2]) / edge.num_traces as f64,
            ];
        } else {
            edge.mean_accel = world_mean;
        }

        // Refine spline: displace interior points by mean acceleration
        // ponytail: uniform displacement, per-segment integration when heading is reliable
        const DISPLACEMENT_SCALE: f64 = 1.0; // 1m per m/s² of mean accel
        let interior_count = edge.spline_points.len().saturating_sub(2);
        for pt in edge.spline_points.iter_mut().skip(1).take(interior_count) {
            pt[0] += edge.mean_accel[0] * DISPLACEMENT_SCALE;
            pt[1] += edge.mean_accel[1] * DISPLACEMENT_SCALE;
            pt[2] += edge.mean_accel[2] * DISPLACEMENT_SCALE * 5.0; // vertical exaggeration
        }
    }
}
