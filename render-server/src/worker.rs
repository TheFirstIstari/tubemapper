use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tokio::time::{interval, Duration};

/// A remote render worker that has registered with this primary server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkerRegistration {
    pub url: String,
    pub capacity: u32,
    pub model_revision: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkerHeartbeat {
    pub url: String,
    pub model_revision: u64,
    pub load: f32,
}

#[derive(Debug, Clone)]
pub struct WorkerState {
    pub url: String,
    pub status: String,
    pub load: f32,
    pub model_revision: u64,
    pub last_seen: tokio::time::Instant,
}

/// Manages distributed render workers.
/// ponytail: simple HashMap + heartbeat timeout.
/// Upgrade to etcd/consul when operating at fleet scale.
pub struct WorkerManager {
    workers: Arc<RwLock<HashMap<String, WorkerState>>>,
    heartbeat_timeout_secs: u64,
}

impl WorkerManager {
    pub fn new(heartbeat_timeout_secs: u64) -> Self {
        Self {
            workers: Arc::new(RwLock::new(HashMap::new())),
            heartbeat_timeout_secs,
        }
    }

    pub fn shared_state(&self) -> Arc<RwLock<HashMap<String, WorkerState>>> {
        self.workers.clone()
    }

    pub async fn register(&self, reg: WorkerRegistration) {
        let mut workers = self.workers.write().await;
        workers.insert(reg.url.clone(), WorkerState {
            url: reg.url,
            status: "active".to_string(),
            load: 0.0,
            model_revision: reg.model_revision,
            last_seen: tokio::time::Instant::now(),
        });
    }

    pub async fn heartbeat(&self, hb: WorkerHeartbeat) {
        let mut workers = self.workers.write().await;
        if let Some(w) = workers.get_mut(&hb.url) {
            w.load = hb.load;
            w.model_revision = hb.model_revision;
            w.last_seen = tokio::time::Instant::now();
            w.status = "active".to_string();
        }
    }

    /// Start a task that evicts stale workers.
    /// ponytail: single tokio task. Upgrade to a proper supervisor when workers > 50.
    pub fn start_eviction_task(&self) {
        let workers = self.workers.clone();
        let timeout = self.heartbeat_timeout_secs;
        tokio::spawn(async move {
            let mut tick = interval(Duration::from_secs(timeout / 2));
            loop {
                tick.tick().await;
                let mut w = workers.write().await;
                let now = tokio::time::Instant::now();
                w.retain(|_, state| {
                    let elapsed = now.duration_since(state.last_seen).as_secs();
                    if elapsed > timeout {
                        state.status = "offline".to_string();
                    }
                    elapsed <= timeout * 2
                });
            }
        });
    }
}
