use axum::response::Html;

const INDEX_HTML: &str = include_str!("../../assets/index.html");

pub async fn serve_ui() -> Html<&'static str> {
    Html(INDEX_HTML)
}
