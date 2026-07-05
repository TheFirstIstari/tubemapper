//! SQLite persistence for traces and model state.
//! ponytail: one table per entity, no migrations framework.
//! Upgrade to sqlx migrate if schema changes become frequent.

use crate::model::Trace;
use chrono::Utc;
use sqlx::sqlite::SqlitePool;

pub async fn init_pool(path: &str) -> SqlitePool {
    let pool = SqlitePool::connect(path).await.unwrap();
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS traces (
            trace_id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            network_id TEXT NOT NULL,
            station_sequence TEXT NOT NULL,
            samples TEXT NOT NULL,
            gps_fixes TEXT NOT NULL,
            uploaded_at TEXT NOT NULL
        )",
    )
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS model_state (
            revision INTEGER NOT NULL DEFAULT 0,
            total_traces INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL
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
            spline_points TEXT NOT NULL
        )",
    )
    .execute(&pool)
    .await
    .unwrap();

    // Seed model state if empty
    let count: (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM model_state")
            .fetch_one(&pool)
            .await
            .unwrap();
    if count.0 == 0 {
        sqlx::query(
            "INSERT INTO model_state (revision, total_traces, updated_at) VALUES (0, 0, ?)",
        )
        .bind(Utc::now().to_rfc3339())
        .execute(&pool)
        .await
        .unwrap();
    }

    pool
}

pub async fn save_trace(pool: &SqlitePool, trace: &Trace) {
    let samples_json = serde_json::to_string(&trace.samples).unwrap();
    let gps_json = serde_json::to_string(&trace.gps_fixes).unwrap();
    let seq_json = serde_json::to_string(&trace.station_sequence).unwrap();
    sqlx::query(
        "INSERT OR REPLACE INTO traces (trace_id, device_id, network_id, station_sequence, samples, gps_fixes, uploaded_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&trace.trace_id)
    .bind(&trace.device_id)
    .bind(&trace.network_id)
    .bind(&seq_json)
    .bind(&samples_json)
    .bind(&gps_json)
    .bind(Utc::now().to_rfc3339())
    .execute(pool)
    .await
    .unwrap();
}

pub async fn load_model_state(pool: &SqlitePool) -> (u64, u64) {
    let row: Result<(i64, i64), _> = sqlx::query_as(
        "SELECT revision, total_traces FROM model_state LIMIT 1",
    )
    .fetch_one(pool)
    .await;
    match row {
        Ok((rev, traces)) => (rev as u64, traces as u64),
        Err(_) => (0, 0),
    }
}

pub async fn save_model_state(pool: &SqlitePool, revision: u64, total_traces: u64) {
    sqlx::query(
        "UPDATE model_state SET revision = ?, total_traces = ?, updated_at = ?",
    )
    .bind(revision as i64)
    .bind(total_traces as i64)
    .bind(Utc::now().to_rfc3339())
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
) {
    let spline_json = serde_json::to_string(spline_points).unwrap();
    sqlx::query(
        "INSERT OR REPLACE INTO edge_stats (edge_id, from_station, to_station, line, num_traces, avg_speed_ms, spline_points)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(edge_id)
    .bind(from)
    .bind(to)
    .bind(line)
    .bind(num_traces as i64)
    .bind(avg_speed_ms)
    .bind(&spline_json)
    .execute(pool)
    .await
    .unwrap();
}

pub async fn load_edge_stats(pool: &SqlitePool) -> Vec<serde_json::Value> {
    let rows: Vec<(String, String, String, String, i64, Option<f64>, String)> = sqlx::query_as(
        "SELECT edge_id, from_station, to_station, line, num_traces, avg_speed_ms, spline_points FROM edge_stats WHERE num_traces > 0",
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    rows.into_iter()
        .map(|(id, from, to, line, n, speed, spline)| {
            let pts: Vec<[f64; 3]> =
                serde_json::from_str(&spline).unwrap_or_default();
            serde_json::json!({
                "id": id,
                "from": from,
                "to": to,
                "line": line,
                "num_traces": n,
                "avg_speed_ms": speed,
                "spline_points": pts,
            })
        })
        .collect()
}
