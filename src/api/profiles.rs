use crate::AppState;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use std::sync::Arc;

pub async fn list_profiles(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let store = state.profiles.read().await;
    let profiles: Vec<_> = store.list().iter().map(|p| p.name.as_str()).collect();
    Json(serde_json::json!({ "profiles": profiles }))
}

pub async fn get_profile(
    State(state): State<Arc<AppState>>,
    Path(name): Path<String>,
) -> impl IntoResponse {
    let store = state.profiles.read().await;
    match store.get(&name) {
        Some(p) => Json(serde_json::json!(p)).into_response(),
        None => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "profile not found"})),
        )
            .into_response(),
    }
}
