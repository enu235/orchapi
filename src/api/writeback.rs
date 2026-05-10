// Server-wide SSE stream that fires when a session with external_task reaches terminal state.

use axum::extract::State;
use axum::response::{IntoResponse, Sse};
use std::convert::Infallible;
use std::sync::Arc;
use tokio_stream::wrappers::BroadcastStream;
use tokio_stream::StreamExt as _;

use crate::AppState;

#[allow(unused_imports)]
pub use crate::manager::WritebackSignal;

pub async fn stream_writeback(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let rx = state.writeback_tx.subscribe();
    let stream = BroadcastStream::new(rx).filter_map(|result| {
        result.ok().map(|signal| {
            let data = serde_json::to_string(&signal).unwrap_or_else(|_| "{}".to_string());
            Ok::<_, Infallible>(
                axum::response::sse::Event::default()
                    .event("writeback")
                    .data(data),
            )
        })
    });
    Sse::new(stream).keep_alive(axum::response::sse::KeepAlive::default())
}
