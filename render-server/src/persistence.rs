use crate::model::Trace;
use sqlx::sqlite::SqlitePool;

pub async fn init_pool(path: &str) -> SqlitePool {
    let abs_path = if path.starts_with('/') {
        path.to_string()
    } else {
        let cwd = std::env::current_dir().unwrap_or_default();
        let full = cwd.join(path);
        full.to_string_lossy().to_string()
    };
    let conn_str = format!("sqlite://{}?mode=rwc", abs_path);
    let pool = SqlitePool::connect(&conn_str).await.unwrap();
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS traces (
            trace_id TEXT PRIMARY KEY,
            journey_id TEXT,
            line_id TEXT,
            from_station TEXT,
            to_station TEXT,
            start_time INTEGER,
            end_time INTEGER,
            sample_count INTEGER,
            device_token TEXT,
            motion_class TEXT
        )",
    )
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS model_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            revision INTEGER NOT NULL DEFAULT 0,
            total_traces INTEGER NOT NULL DEFAULT 0
        )",
    )
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS edge_stats (
            edge_id TEXT PRIMARY KEY,
            from_station TEXT NOT NULL,
            to_station TEXT NOT NULL,
            line TEXT NOT NULL,
            num_traces INTEGER NOT NULL DEFAULT 0,
            avg_speed_ms REAL,
            spline_points TEXT NOT NULL,
            mean_accel TEXT NOT NULL DEFAULT '[0,0,0]'
        )",
    )
    .execute(&pool)
    .await
    .unwrap();

    // Ensure model_state has a row
    sqlx::query(
        "INSERT OR IGNORE INTO model_state (id, revision, total_traces) VALUES (1, 0, 0)",
    )
    .execute(&pool)
    .await
    .unwrap();

    pool
}

pub async fn save_trace(pool: &SqlitePool, trace: &Trace) {
    let start_time = trace
        .samples
        .first()
        .map(|s| s.timestamp as i64)
        .unwrap_or(0);
    let end_time = trace
        .samples
        .last()
        .map(|s| s.timestamp as i64)
        .unwrap_or(0);
    sqlx::query(
        "INSERT OR REPLACE INTO traces \
         (trace_id, journey_id, line_id, from_station, to_station, \
          start_time, end_time, sample_count, device_token, motion_class) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&trace.trace_id)
    .bind(&trace.device_id)
    .bind("")  // line_id — not used in current schema
    .bind(trace.station_sequence.first().map(|s| s.as_str()).unwrap_or(""))
    .bind(trace.station_sequence.last().map(|s| s.as_str()).unwrap_or(""))
    .bind(start_time)
    .bind(end_time)
    .bind(trace.samples.len() as i64)
    .bind(&trace.device_id)
    .bind(
        trace
            .station_sequence
            .first()
            .map(|_| "train")
            .unwrap_or("unknown"),
    )
    .execute(pool)
    .await
    .unwrap();
}

pub async fn load_model_state(pool: &SqlitePool) -> (u64, u64) {
    let row: Option<(i64, i64)> =
        sqlx::query_as("SELECT revision, total_traces FROM model_state WHERE id = 1")
            .fetch_optional(pool)
            .await
            .unwrap_or(None);
    match row {
        Some((rev, traces)) => (rev as u64, traces as u64),
        None => (0, 0),
    }
}

pub async fn save_model_state(pool: &SqlitePool, revision: u64, total_traces: u64) {
    sqlx::query(
        "UPDATE model_state SET revision = ?, total_traces = ? WHERE id = 1",
    )
    .bind(revision as i64)
    .bind(total_traces as i64)
    .execute(pool)
    .await
    .unwrap();
}

pub async fn save_edge_stats(
    pool: &SqlitePool,
    edge_id: &str,
    from: &str,
    to: &str,
    line: &str,
    num_traces: u64,
    avg_speed_ms: Option<f64>,
    spline_points: &[[f64; 3]],
    mean_accel: [f64; 3],
) {
    let spline_json = serde_json::to_string(spline_points).unwrap();
    let accel_json = serde_json::to_string(&mean_accel).unwrap();
    sqlx::query(
        "INSERT OR REPLACE INTO edge_stats (edge_id, from_station, to_station, line, num_traces, avg_speed_ms, spline_points, mean_accel)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(edge_id)
    .bind(from)
    .bind(to)
    .bind(line)
    .bind(num_traces as i64)
    .bind(avg_speed_ms)
    .bind(&spline_json)
    .bind(&accel_json)
    .execute(pool)
    .await
    .unwrap();
}

pub async fn load_edge_stats(pool: &SqlitePool) -> Vec<serde_json::Value> {
    let rows: Vec<(String, String, String, String, i64, Option<f64>, String, String)> = sqlx::query_as(
        "SELECT edge_id, from_station, to_station, line, num_traces, avg_speed_ms, spline_points, mean_accel FROM edge_stats WHERE num_traces > 0",
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    rows.into_iter()
        .map(|(id, from, to, line, n, speed, spline, accel)| {
            let pts: Vec<[f64; 3]> =
                serde_json::from_str(&spline).unwrap_or_default();
            let mean_accel: [f64; 3] =
                serde_json::from_str(&accel).unwrap_or([0.0, 0.0, 0.0]);
            serde_json::json!({
                "id": id,
                "from": from,
                "to": to,
                "line": line,
                "num_traces": n,
                "avg_speed_ms": speed,
                "spline_points": pts,
                "mean_accel": mean_accel,
            })
        })
        .collect()
}
