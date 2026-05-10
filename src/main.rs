use anyhow::Result;
use axum::{
    routing::{get, post},
    Router,
};
use clap::Parser;
use config::{AppConfig, ProfileStore};
use std::{net::SocketAddr, path::PathBuf, sync::Arc};
use tokio::sync::RwLock;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use tracing::info;

mod adapters;
mod api;
mod config;
mod log_writer;
mod manager;
mod outcome;
mod spec;
mod store;

use manager::{SessionManager, WritebackSignal};

#[derive(Parser)]
#[command(name = "orchapi", version, about = "Local agent orchestration server")]
struct Cli {
    #[arg(long, env = "ORCHAPI_CONFIG", default_value = "config.toml")]
    config: PathBuf,
}

pub struct AppState {
    pub config: AppConfig,
    pub manager: Arc<SessionManager>,
    pub profiles: Arc<RwLock<ProfileStore>>,
    pub writeback_tx: tokio::sync::broadcast::Sender<WritebackSignal>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .init();

    let cli = Cli::parse();
    let cfg = AppConfig::load(&cli.config).unwrap_or_else(|e| {
        tracing::warn!("Config load error ({e}), using defaults");
        AppConfig::default()
    });

    std::fs::create_dir_all(&cfg.server.data_dir)?;

    let profiles_dir = PathBuf::from("profiles");
    let profile_store = ProfileStore::load(&profiles_dir).unwrap_or_else(|e| {
        tracing::warn!("Profile load error ({e}), starting with empty store");
        ProfileStore {
            profiles: Default::default(),
        }
    });
    info!("Loaded {} profiles", profile_store.profiles.len());

    let pool = store::create_pool(&cfg.server.data_dir).await?;
    store::run_migrations(&pool).await?;

    let cancelled = store::mark_running_as_cancelled(&pool, "server_startup").await?;
    if cancelled > 0 {
        tracing::warn!("Marked {cancelled} stale sessions as cancelled on startup");
    }

    let (writeback_tx, _) = tokio::sync::broadcast::channel::<WritebackSignal>(128);
    let manager = Arc::new(SessionManager::new(
        pool.clone(),
        &cfg,
        writeback_tx.clone(),
    ));
    let state = Arc::new(AppState {
        config: cfg.clone(),
        manager,
        profiles: Arc::new(RwLock::new(profile_store)),
        writeback_tx,
    });

    let app = Router::new()
        .route("/sessions", post(api::sessions::create_session))
        .route("/sessions", get(api::sessions::list_sessions))
        .route("/sessions/:id", get(api::sessions::get_session))
        .route("/sessions/:id/logs", get(api::sessions::get_logs))
        .route("/sessions/:id/stream", get(api::sessions::stream_session))
        .route("/sessions/:id/cancel", post(api::sessions::cancel_session))
        .route(
            "/sessions/:id/events",
            post(api::sessions::post_session_event).get(api::sessions::get_session_events),
        )
        .route(
            "/sessions/:id/writeback-claim",
            post(api::sessions::claim_writeback),
        )
        .route(
            "/sessions/:id/writeback-ack",
            post(api::sessions::ack_writeback),
        )
        .route("/writeback/stream", get(api::writeback::stream_writeback))
        .route("/profiles", get(api::profiles::list_profiles))
        .route("/profiles/:name", get(api::profiles::get_profile))
        .route("/healthz", get(healthz))
        .route("/ui", get(api::ui::serve_ui))
        .with_state(state)
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive());

    let addr: SocketAddr = cfg.server.bind.parse()?;
    info!("orchapi listening on http://{addr}");
    info!("Dashboard: http://{addr}/ui");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn healthz(
    axum::extract::State(state): axum::extract::State<Arc<AppState>>,
) -> axum::Json<serde_json::Value> {
    let counts = store::count_by_status(state.manager.pool())
        .await
        .unwrap_or_default();
    axum::Json(serde_json::json!({
        "status": "ok",
        "version": env!("CARGO_PKG_VERSION"),
        "counts": counts,
    }))
}
