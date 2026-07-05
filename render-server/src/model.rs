use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::collections::HashSet;

/// A rail/metro network loaded from a network definition JSON.
#[derive(Debug, Clone, Deserialize)]
pub struct NetworkDefinition {
    pub id: String,
    pub name: String,
    pub lines: Vec<LineDef>,
    pub stations: Vec<StationDef>,
    pub edges: Vec<EdgeDef>,
    #[serde(skip)]
    pub station_ids: HashSet<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct LineDef {
    pub id: String,
    pub name: String,
    pub color: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct StationDef {
    pub id: String,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub elevation: f64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct EdgeDef {
    pub id: String,
    pub from: String,
    pub to: String,
    pub line: String,
    pub direction: String,
    pub length_m: u32,
    pub track_km: f64,
}

impl NetworkDefinition {
    pub fn load(path: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let content = std::fs::read_to_string(path)?;
        let mut net: NetworkDefinition = serde_json::from_str(&content)?;
        net.station_ids = net.stations.iter().map(|s| s.id.clone()).collect();
        Ok(net)
    }
}

// ponytail: same as NetworkDefinition::load, convenience for main.rs
pub fn load_network(path: &str) -> Result<NetworkDefinition, Box<dyn std::error::Error>> {
    NetworkDefinition::load(path)
}

/// The live, optimized graph that the render server maintains.
/// Starts as the prior (straight lines between stations), refines with each trace.
#[derive(Debug, Clone)]
pub struct TubeGraph {
    pub revision: u64,
    pub total_traces: u64,
    pub stations: Vec<Station>,
    pub edges: Vec<Edge>,
}

#[derive(Debug, Clone)]
pub struct Station {
    pub id: String,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub elevation: f64,
}

#[derive(Debug, Clone)]
pub struct Edge {
    pub id: String,
    pub from: String,
    pub to: String,
    pub line: String,
    pub length_m: u32,
    // Spline control points: each is [x, y, z] in local coords.
    // ponytail: simple linear interpolation between stations as prior.
    // Upgrade to Catmull-Rom spline with multiple control points when optimizing.
    pub spline_points: Vec<[f64; 3]>,
    pub num_traces: u64,
    pub motion_samples: HashMap<String, u64>, // motion_class → sample count
}

/// A sensor trace uploaded from the mobile app.
#[derive(Debug, Clone, Deserialize)]
pub struct Trace {
    pub trace_id: String,
    pub device_id: String,
    pub network_id: String,
    pub station_sequence: Vec<String>,
    pub samples: Vec<SensorSample>,
    pub gps_fixes: Vec<GpsFix>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SensorSample {
    pub timestamp: f64,
    pub accelerometer: [f64; 3],
    pub gyroscope: [f64; 3],
    pub magnetometer: [f64; 3],
    pub raw_accel: [f64; 3],
    pub motion_class: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GpsFix {
    pub timestamp: f64,
    pub lat: f64,
    pub lon: f64,
    pub accuracy_m: f32,
    pub elevation_m: f32,
}

impl TubeGraph {
    pub fn from_network(net: &NetworkDefinition) -> Self {
        let stations: Vec<Station> = net
            .stations
            .iter()
            .map(|s| Station {
                id: s.id.clone(),
                name: s.name.clone(),
                lat: s.lat,
                lon: s.lon,
                elevation: s.elevation,
            })
            .collect();

        let edges: Vec<Edge> = net
            .edges
            .iter()
            .map(|e| {
                let from_station = net.stations.iter().find(|s| s.id == e.from).unwrap();
                let to_station = net.stations.iter().find(|s| s.id == e.to).unwrap();
                // ponytail: prior spline = straight line between stations + midpoint at half elevation
                // Once we have real traces, this gets refined
                let spline_points = vec![
                    [from_station.lat, from_station.lon, from_station.elevation],
                    [
                        (from_station.lat + to_station.lat) / 2.0,
                        (from_station.lon + to_station.lon) / 2.0,
                        (from_station.elevation + to_station.elevation) / 2.0,
                    ],
                    [to_station.lat, to_station.lon, to_station.elevation],
                ];

                Edge {
                    id: e.id.clone(),
                    from: e.from.clone(),
                    to: e.to.clone(),
                    line: e.line.clone(),
                    length_m: e.length_m,
                    spline_points,
                    num_traces: 0,
                    motion_samples: HashMap::new(),
                }
            })
            .collect();

        TubeGraph {
            revision: 0,
            total_traces: 0,
            stations,
            edges,
        }
    }
}
