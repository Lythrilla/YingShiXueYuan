use axum::{
    body::Body,
    http::{header, StatusCode, Uri},
    response::{IntoResponse, Response},
};
use rust_embed::RustEmbed;

/// 编译期把构建好的前端静态资源嵌入二进制，实现单文件部署。
#[derive(RustEmbed)]
#[folder = "../frontend/dist/"]
struct Assets;

pub async fn static_handler(uri: Uri) -> Response {
    let path = uri.path().trim_start_matches('/');
    let path = if path.is_empty() { "index.html" } else { path };

    if let Some(content) = Assets::get(path) {
        return serve(path, content.data.into_owned());
    }

    // SPA 回退：未知路径返回 index.html，由前端路由处理。
    match Assets::get("index.html") {
        Some(content) => serve("index.html", content.data.into_owned()),
        None => (
            StatusCode::NOT_FOUND,
            "前端资源缺失：请先执行 `npm run build` 再编译后端。",
        )
            .into_response(),
    }
}

fn serve(path: &str, body: Vec<u8>) -> Response {
    let mime = mime_guess::from_path(path).first_or_octet_stream();
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, mime.as_ref())
        .body(Body::from(body))
        .unwrap()
}
