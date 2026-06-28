//! 厂商离线推送：服务器在新预约 / 开门提醒时，直接调用厂商推送 REST API，
//! 由手机系统级推送进程下发通知，使 App 即便被杀 / 不在前台也能收到。
//!
//! 目前覆盖：
//! - 华为 HMS Push（HUAWEI Push Kit）—— 覆盖华为设备
//! - OPPO / 一加 Heytap Push —— 覆盖 OPPO、一加（ColorOS/氢OS 同源）设备
//!
//! 未配置凭据的厂商会被自动跳过（见 `PushConfig`）。

use std::time::Duration;

use serde_json::json;
use sha2::{Digest, Sha256};

use crate::config::{HuaweiPush, OppoPush, PushConfig};
use crate::models::DeviceToken;

const HTTP_TIMEOUT: Duration = Duration::from_secs(15);

const VENDOR_HUAWEI: &str = "huawei";
const VENDOR_OPPO: &str = "oppo";

/// 把一批设备令牌按厂商分组并下发通知。错误只记录日志，不影响主流程。
pub async fn dispatch(cfg: &PushConfig, tokens: Vec<DeviceToken>, title: &str, body: &str) {
    if cfg.is_empty() || tokens.is_empty() {
        return;
    }

    let client = match reqwest::Client::builder().timeout(HTTP_TIMEOUT).build() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("推送：创建 HTTP 客户端失败：{e}");
            return;
        }
    };

    let huawei: Vec<String> = collect(&tokens, VENDOR_HUAWEI);
    let oppo: Vec<String> = collect(&tokens, VENDOR_OPPO);

    if let (Some(hw), false) = (&cfg.huawei, huawei.is_empty()) {
        if let Err(e) = huawei_send(&client, hw, &huawei, title, body).await {
            eprintln!("推送：华为下发失败：{e}");
        }
    }
    if let (Some(op), false) = (&cfg.oppo, oppo.is_empty()) {
        if let Err(e) = oppo_send(&client, op, &oppo, title, body).await {
            eprintln!("推送：OPPO 下发失败：{e}");
        }
    }
}

fn collect(tokens: &[DeviceToken], vendor: &str) -> Vec<String> {
    tokens
        .iter()
        .filter(|t| t.vendor == vendor && !t.token.is_empty())
        .map(|t| t.token.clone())
        .collect()
}

// ---------- 华为 HMS Push ----------
// 文档：https://developer.huawei.com/consumer/cn/doc/HMSCore-Guides/https-send-api-0000001050986197
async fn huawei_send(
    client: &reqwest::Client,
    cfg: &HuaweiPush,
    tokens: &[String],
    title: &str,
    body: &str,
) -> Result<(), String> {
    let access_token = huawei_access_token(client, cfg).await?;
    let url = format!(
        "https://push-api.cloud.huawei.com/v1/{}/messages:send",
        cfg.app_id
    );
    // click_action.type = 3 表示点击通知打开应用首页。
    let payload = json!({
        "validate_only": false,
        "message": {
            "android": {
                "notification": {
                    "title": title,
                    "body": body,
                    "click_action": { "type": 3 }
                }
            },
            "token": tokens,
        }
    });
    let resp = client
        .post(&url)
        .bearer_auth(&access_token)
        .json(&payload)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    // HMS 成功时 code 为 "80000000"。
    if !status.is_success() || !text.contains("80000000") {
        return Err(format!("HTTP {status}：{text}"));
    }
    Ok(())
}

async fn huawei_access_token(
    client: &reqwest::Client,
    cfg: &HuaweiPush,
) -> Result<String, String> {
    let resp = client
        .post("https://oauth-login.cloud.huawei.com/oauth2/v3/token")
        .form(&[
            ("grant_type", "client_credentials"),
            ("client_id", cfg.app_id.as_str()),
            ("client_secret", cfg.client_secret.as_str()),
        ])
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(format!("获取 access_token 失败 HTTP {status}：{text}"));
    }
    let value: serde_json::Value = resp.json().await.map_err(|e| e.to_string())?;
    value
        .get("access_token")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "响应中缺少 access_token".to_string())
}

// ---------- OPPO / 一加 Heytap Push ----------
// 文档：https://open.oppomobile.com/new/developmentDoc/info?id=11227
async fn oppo_send(
    client: &reqwest::Client,
    cfg: &OppoPush,
    tokens: &[String],
    title: &str,
    body: &str,
) -> Result<(), String> {
    let auth_token = oppo_auth_token(client, cfg).await?;
    // Heytap 单推按 registration_id 逐台下发。
    let mut last_err: Option<String> = None;
    for token in tokens {
        // target_type = 2 表示按 registration_id 定向。click_action_type = 0 打开应用。
        let message = json!({
            "target_type": 2,
            "target_value": token,
            "notification": {
                "title": title,
                "content": body,
                "click_action_type": 0
            }
        })
        .to_string();
        let resp = client
            .post("https://api.push.oppomobile.com/server/v1/message/notification/unicast")
            .header("auth_token", auth_token.as_str())
            .form(&[("message", message.as_str())])
            .send()
            .await
            .map_err(|e| e.to_string());
        match resp {
            Ok(r) => {
                let status = r.status();
                let text = r.text().await.unwrap_or_default();
                // Heytap 成功 code 为 0。
                if !status.is_success() || !text.contains("\"code\":0") {
                    last_err = Some(format!("HTTP {status}：{text}"));
                }
            }
            Err(e) => last_err = Some(e),
        }
    }
    match last_err {
        Some(e) => Err(e),
        None => Ok(()),
    }
}

async fn oppo_auth_token(client: &reqwest::Client, cfg: &OppoPush) -> Result<String, String> {
    let timestamp = chrono::Utc::now().timestamp_millis().to_string();
    // sign = sha256(app_key + timestamp + master_secret) 的十六进制小写。
    let sign = sha256_hex(&format!("{}{}{}", cfg.app_key, timestamp, cfg.master_secret));
    let resp = client
        .post("https://api.push.oppomobile.com/server/v1/auth")
        .form(&[
            ("app_key", cfg.app_key.as_str()),
            ("sign", sign.as_str()),
            ("timestamp", timestamp.as_str()),
        ])
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(format!("获取 auth_token 失败 HTTP {status}：{text}"));
    }
    let value: serde_json::Value = resp.json().await.map_err(|e| e.to_string())?;
    value
        .get("data")
        .and_then(|d| d.get("auth_token"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| format!("响应中缺少 auth_token：{value}"))
}

fn sha256_hex(input: &str) -> String {
    let digest = Sha256::digest(input.as_bytes());
    let mut out = String::with_capacity(digest.len() * 2);
    for byte in digest {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}
