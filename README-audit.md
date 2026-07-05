# Render Server Audit

## Bug: Pipeline panics on empty station_sequence
`pipeline.rs:30` — `let windows = trace.station_sequence.windows(3)` crashes if 0-2 stations provided. No validation before processing.

## Bug: Pipeline panics on missing stations
`pipeline.rs:46` — `graph.stations.get(&edge.from).unwrap()` crashes if station_sequence references stations not in the network graph. No input validation.

## Bug: All persistence operations unwrap
`persistence.rs` — Every SQL query uses `.unwrap()`. A single DB failure (disk full, locked file, schema mismatch) kills the entire server process. All SQL operations should return `Result` and the HTTP handlers should return 500 errors.

## Bug: process_trace is declared async but contains no async work
`pipeline.rs:6` — `pub async fn process_trace(...)` uses `async` but the function has zero `.await` calls. The `async` is misleading and forces callers to handle a future for synchronous work.

## Bug: Graph write lock held during pipeline processing
`main.rs:103` — `state.graph.write().await` is acquired before calling `process_trace()` and held for the entire duration of the pipeline iteration. If processing takes significant time, all read requests (status, model, network, workers) will block.

## Bug: Worker tokens generated but never validated
`worker.rs` — `register_worker` generates a signed token. No endpoint validates this token on worker requests. The token field exists but is unused for auth.

## Bug: Network loaded once, never refreshed
`main.rs:191` — Network definition JSON is loaded at startup and never reloaded. There's no endpoint to submit a network update. If the network definition changes, the server needs a restart.

## Bug: Spline displacement scale too small to be meaningful
`pipeline.rs:93` — `DISPLACEMENT_SCALE = 0.01` means acceleration of 1 m/s² displaces spline points by 1cm. For a 500m tunnel edge, this is invisible in the 3D model. Should be network-scale (meters, not centimeters).

## Design: Unused NetworkDefinition import in main.rs
`main.rs` contained `use crate::model::NetworkDefinition` before `compute_avg_speed` was removed. It may still be imported but unused.

## Design: Missing Cargo edition
`Cargo.toml` doesn't specify an edition field. This defaults to Rust 2015 which doesn't support `async fn`. The project compiles because of edition resolution from the workspace/rustc default but should be explicit.

## Design: Trace ID collisions
`POST /api/v1/trace` accepts a `trace_id` from the client. Two devices could submit the same trace_id, causing an `INSERT OR REPLACE` silent overwrite. Server should generate trace IDs.

## Design: No input size limits
A trace can contain unlimited samples or station sequences. A malicious client could upload a multi-GB trace and OOM the server. Need max_samples and max_stations limits.

## Design: No model revision locking
Two concurrent POST /api/v1/trace requests could interleave their read-modify-write cycles, causing lost updates to edge_stats and incorrect revision numbers.
