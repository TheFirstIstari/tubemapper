use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde::Serialize;
use sqlx::sqlite::SqlitePool;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;
use tracing::info;

mod model;
mod persistence;
mod pipeline;
mod worker;

use model::{NetworkDefinition, TubeGraph, Trace};
use worker::{WorkerHeartbeat, WorkerManager, WorkerRegistration};

const DB_PATH: &str = "tubemapper.db";

#[derive(Clone)]
struct AppState {
    graph: Arc<RwLock<TubeGraph>>,
    network: NetworkDefinition,
    pool: SqlitePool,
    worker_manager: Arc<WorkerManager>,
    start_time: Instant,
}

#[derive(Serialize)]
struct StatusResponse {
    network_id: String,
    network_name: String,
    model_revision: u64,
    total_traces: u64,
    stations: usize,
    edges: usize,
    workers: Vec<serde_json::Value>,
    uptime_seconds: u64,
}

#[derive(Serialize)]
struct TraceUploadResponse {
    trace_id: String,
    accepted: bool,
    model_revision_bumped: u64,
    message: String,
}

async fn status(State(state): State<AppState>) -> Json<StatusResponse> {
    let graph = state.graph.read().await;
    let workers_arc = state.worker_manager.shared_state();
    let workers = workers_arc.read().await;
    let worker_list: Vec<serde_json::Value> = workers
        .values()
        .map(|w| {
            serde_json::json!({
                "url": w.url,
                "status": w.status,
                "load": w.load,
                "model_revision": w.model_revision,
            })
        })
        .collect();

    Json(StatusResponse {
        network_id: state.network.id.clone(),
        network_name: state.network.name.clone(),
        model_revision: graph.revision,
        total_traces: graph.total_traces,
        stations: graph.stations.len(),
        edges: graph.edges.len(),
        workers: worker_list,
        uptime_seconds: state.start_time.elapsed().as_secs(),
    })
}

async fn upload_trace(
    State(state): State<AppState>,
    Json(trace): Json<Trace>,
) -> Result<Json<TraceUploadResponse>, StatusCode> {
    let trace_id = trace.trace_id.clone();

    // Validate station sequence
    for station_id in &trace.station_sequence {
        if !state.network.station_ids.contains(station_id) {
            return Err(StatusCode::BAD_REQUEST);
        }
    }

    // Process trace
    let rev = {
        let mut graph = state.graph.write().await;
        pipeline::process_trace(&trace, &mut graph).await
    };

    // Persist
    persistence::save_trace(&state.pool, &trace).await;
    persistence::save_model_state(&state.pool, rev, {
        let g = state.graph.read().await;
        g.total_traces
    })
    .await;

    // Persist edge stats
    let graph_snapshot = { state.graph.read().await.clone() };
    for edge in &graph_snapshot.edges {
        let avg_speed = compute_avg_speed(edge, &state.network);
        persistence::save_edge_stats(
            &state.pool,
            &edge.id,
            &edge.from,
            &edge.to,
            &edge.line,
            edge.num_traces,
            avg_speed,
            &edge.spline_points,
        )
        .await;
    }

    info!("Trace {} processed -> revision {}", trace_id, rev);

    Ok(Json(TraceUploadResponse {
        trace_id,
        accepted: true,
        model_revision_bumped: rev,
        message: format!("trace processed, {} samples", trace.samples.len()),
    }))
}

/// ponytail: rough avg speed = edge length / dwell time estimate.
/// Real fix: use timestamp-delta between first/last sample on edge.
fn compute_avg_speed(edge: &model::Edge, _net: &NetworkDefinition) -> Option<f64> {
    if edge.num_traces == 0 {
        return None;
    }
    // ponytail: assume 30s average dwell between stations
    let dwell_s = 30.0;
    Some(edge.length_m as f64 / dwell_s)
}

async fn get_model(State(state): State<AppState>) -> Json<serde_json::Value> {
    let graph = state.graph.read().await;
    let edge_stats = persistence::load_edge_stats(&state.pool).await;

    Json(serde_json::json!({
        "revision": graph.revision,
        "network": state.network.id,
        "network_name": state.network.name,
        "stations": graph.stations.iter().map(|s| {
            serde_json::json!({
                "id": s.id,
                "name": s.name,
                "lat": s.lat,
                "lon": s.lon,
                "elevation": s.elevation,
            })
        }).collect::<Vec<_>>(),
        "lines": state.network.lines.iter().map(|l| {
            serde_json::json!({
                "id": l.id,
                "name": l.name,
                "color": l.color,
            })
        }).collect::<Vec<_>>(),
        "edges": edge_stats,
    }))
}

async fn register_worker(
    State(state): State<AppState>,
    Json(reg): Json<WorkerRegistration>,
) -> StatusCode {
    state.worker_manager.register(reg).await;
    StatusCode::OK
}

async fn worker_heartbeat(
    State(state): State<AppState>,
    Json(hb): Json<WorkerHeartbeat>,
) -> StatusCode {
    state.worker_manager.heartbeat(hb).await;
    StatusCode::OK
}

/// GET /api/v1/network — download the full network definition
async fn get_network(State(state): State<AppState>) -> Json<serde_json::Value> {
    let net = &state.network;
    Json(serde_json::json!({
        "id": net.id,
        "name": net.name,
        "lines": net.lines,
        "stations": net.stations,
        "edges": net.edges,
    }))
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    // Database
    let pool = persistence::init_pool(DB_PATH).await;
    let (saved_revision, saved_traces) = persistence::load_model_state(&pool).await;

    // Load network definition
    let network_path = std::env::var("TUBEMAPPER_NETWORK")
        .unwrap_or_else(|_| "../NetworkDefinitions/london-underground.json".to_string());

    let network = model::load_network(&network_path)
        .expect("failed to load network definition");

    let mut graph = TubeGraph::from_network(&network);

    // Restore previously saved state
    graph.revision = saved_revision;
    graph.total_traces = saved_traces;
    // ponytail: edge stats from persistence are loaded on-demand in get_model.
    // In-memory edge state starts from network definition and accumulates from new traces.

    info!(
        "Loaded network: {} ({} stations, {} edges), saved revision={}, traces={}",
        network.name,
        network.stations.len(),
        network.edges.len(),
        saved_revision,
        saved_traces
    );

    // Worker manager
    let worker_manager = Arc::new(WorkerManager::new(60));
    worker_manager.start_eviction_task();

    let state = AppState {
        graph: Arc::new(RwLock::new(graph)),
        network,
        pool,
        worker_manager,
        start_time: Instant::now(),
    };

    let app = Router::new()
        .route("/api/v1/status", get(status))
        .route("/api/v1/trace", post(upload_trace))
        .route("/api/v1/model", get(get_model))
        .route("/api/v1/network", get(get_network))
        .route("/api/v1/workers/register", post(register_worker))
        .route("/api/v1/workers/heartbeat", post(worker_heartbeat))
        .layer(tower_http::cors::CorsLayer::permissive())
        .with_state(state);

    let addr = "0.0.0.0:3000";
    info!("Render server listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
