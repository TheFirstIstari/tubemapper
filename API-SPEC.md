# API Specification

## Current Endpoints

| Method | Path | Status |
|--------|------|--------|
| GET | /api/v1/status | ✅ |
| POST | /api/v1/trace | ✅ |
| GET | /api/v1/model | ✅ |
| GET | /api/v1/network | ✅ |
| POST | /api/v1/workers/register | ✅ Stub |
| POST | /api/v1/workers/heartbeat | ✅ Stub |

## Missing CRUD Endpoints

### 1. DELETE /api/v1/trace/:trace_id — Delete a single trace
Response: `{"deleted": true, "model_revision_bumped": 1}`
Impact: Decrement edge_stats for affected edges, recalculate spline priors, bump revision.

### 2. GET /api/v1/traces — List all traces (with pagination)
Query params: `?limit=50&offset=0&device_id=optional`
Response:
```json
{
  "traces": [{
    "trace_id": "uuid",
    "device_id": "anon-abc123",
    "station_sequence": ["euston", "warren-street"],
    "sample_count": 240,
    "start_time": 1712345678,
    "end_time": 1712345890,
    "motion_class_counts": {"train": 200, "stationary": 40}
  }],
  "total": 142,
  "limit": 50,
  "offset": 0
}
```

### 3. GET /api/v1/trace/:trace_id — Get single trace details
Returns full trace metadata + sample count. Not the raw samples (too large).

### 4. POST /api/v1/network/upload — Upload/update network definition
Body: Full NetworkDefinition JSON
Response: `{"network_id": "london-underground", "stations": 279, "edges": 362}`
Impact: Clears existing graph, rebuilds from uploaded definition, bumps revision.

### 5. GET /api/v1/edges/:edge_id/stats — Per-edge detailed statistics
```json
{
  "edge_id": "euston-warren-street-northern",
  "num_traces": 47,
  "avg_speed_ms": 12.3,
  "speed_std": 2.1,
  "spline_points": [[...], ...],
  "mean_accel": [0.3, 0.1, 0.0],
  "accel_std": [0.1, 0.05, 0.02],
  "motion_class_distribution": {"train": 40, "stationary": 7},
  "traces": ["trace-id-1", "trace-id-2"]
}
```

### 6. POST /api/v1/reset — Reset all data
Body: `{"confirm": "delete all data"}`
Response: `{"deleted_traces": 142, "new_revision": 0}`
Impact: Clears traces, edge_stats, model_state tables. Resets revision to 0.

## Model Output Versioning

The GET /api/v1/model endpoint should support versioning:

```http
GET /api/v1/model?v=2
Accept: application/vnd.tubemapper.model+json;version=2
```

v1 (current): lat/lon coordinates, 10-point linear spline
v2 (proposed): ENU coordinates, Catmull-Rom spline with 4 control points per segment, per-edge statistics

The model endpoint should include:
```json
{
  "revision": 147,
  "format_version": 2,
  "edges": [...]
}
```

## Model Revision Endpoint

### GET /api/v1/model/revisions — List all model revisions
```json
{
  "revisions": [
    {"revision": 1, "timestamp": "2026-07-05T12:00:00Z", "traces_included": 1},
    {"revision": 147, "timestamp": "2026-07-05T16:30:00Z", "traces_included": 142}
  ]
}
```

## SQLite Schema Changes

### Add `device_id` index to traces
```sql
CREATE INDEX idx_traces_device_id ON traces(device_id);
```

### Add `traces_in_revision` table for tracking which traces contributed to which revision
```sql
CREATE TABLE traces_in_revision (
    revision INTEGER NOT NULL,
    trace_id TEXT NOT NULL,
    PRIMARY KEY (revision, trace_id)
);
```

### Add `trace_edges` junction table for quick per-edge trace lookup
```sql
CREATE TABLE trace_edges (
    trace_id TEXT NOT NULL,
    edge_id TEXT NOT NULL,
    sample_count INTEGER NOT NULL DEFAULT 0,
    dwell_ms INTEGER NOT NULL DEFAULT 0,
    motion_class TEXT NOT NULL DEFAULT 'unknown',
    PRIMARY KEY (trace_id, edge_id)
);
```

### Add `mean_accel_std` to edge_stats
```sql
ALTER TABLE edge_stats ADD COLUMN mean_accel_std TEXT NOT NULL DEFAULT '[0,0,0]';
```

### Add trace deletion support to edge_stats
```sql
-- Soft delete support
ALTER TABLE traces ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;
```

## Worker Distribution API Evolution

The current worker API is a stub. For production:

1. **Worker registration** should validate capabilities against a known whitelist
2. **Heartbeat** should include work-in-progress status
3. **Work assignment** endpoint:
   ```
   POST /api/v1/workers/:id/assign
   Body: {"edge_ids": ["e1", "e2", ...]}
   Response: {"assigned": ["e1", "e2"], "work_token": "xyz"}
   ```
4. **Work completion** endpoint:
   ```
   POST /api/v1/workers/:id/complete
   Body: {"work_token": "xyz", "results": {edge_stats...}}
   ```
5. **Worker capacity** should be tracked and used for scheduling decisions
6. **Worker auto-scaling** is out of scope for v1
