use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use hmac::{Hmac, Mac};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

/// 签发一个 `base64(payload).base64(hmac)` 形式的 token。
/// payload = `username|issued_at_unix`。
pub fn create_token(secret: &str, username: &str) -> String {
    let issued = chrono::Utc::now().timestamp();
    let payload = format!("{}|{}", username, issued);
    let sig = sign(secret, payload.as_bytes());
    format!(
        "{}.{}",
        URL_SAFE_NO_PAD.encode(payload.as_bytes()),
        URL_SAFE_NO_PAD.encode(sig)
    )
}

/// 校验 token，返回用户名；失败返回 Err(原因)。
pub fn verify_token(secret: &str, token: &str, max_age: i64) -> Result<String, &'static str> {
    let (payload_b64, sig_b64) = token.split_once('.').ok_or("无效的登录凭证")?;
    let payload = URL_SAFE_NO_PAD
        .decode(payload_b64)
        .map_err(|_| "无效的登录凭证")?;
    let sig = URL_SAFE_NO_PAD
        .decode(sig_b64)
        .map_err(|_| "无效的登录凭证")?;

    let expected = sign(secret, &payload);
    if !constant_time_eq(&expected, &sig) {
        return Err("无效的登录凭证");
    }

    let payload_str = String::from_utf8(payload).map_err(|_| "无效的登录凭证")?;
    let (username, issued) = payload_str.split_once('|').ok_or("无效的登录凭证")?;
    let issued: i64 = issued.parse().map_err(|_| "无效的登录凭证")?;
    if chrono::Utc::now().timestamp() - issued > max_age {
        return Err("登录已过期，请重新登录");
    }
    Ok(username.to_string())
}

/// 用 secret 作为盐，对密码做 HMAC-SHA256 派生，避免明文存库。
pub fn hash_password(secret: &str, password: &str) -> String {
    URL_SAFE_NO_PAD.encode(sign(secret, password.as_bytes()))
}

/// 常量时间比较密码哈希。
pub fn verify_password(secret: &str, password: &str, hash: &str) -> bool {
    let expected = hash_password(secret, password);
    constant_time_eq(expected.as_bytes(), hash.as_bytes())
}

fn sign(secret: &str, data: &[u8]) -> Vec<u8> {
    let mut mac =
        HmacSha256::new_from_slice(secret.as_bytes()).expect("hmac accepts any key length");
    mac.update(data);
    mac.finalize().into_bytes().to_vec()
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}
