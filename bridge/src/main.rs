//! JSON CLI / 常驻 serve bridge：SodaPlus ↔ libresoda。
//!
//! 扫码登录必须同进程保活 Chromium/CDP cookie jar（对齐 SodaM / libresoda QR-LOGIN.md）。
//! `serve` 模式：stdin 每行一条 JSON 请求，stdout 回一条 JSON 响应。

use serde::Deserialize;
use serde_json::{json, Value};
use std::env;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

const DEFAULT_SIGNER_URL: &str = "http://103.236.75.83:8899/sign";
const DEFAULT_SIGNER_TOKEN: &str = "b356ad402bc31ee9e5a99cfdbf41eaa39961a562251c3359";

fn print_json(value: &impl serde::Serialize) {
    println!("{}", serde_json::to_string(value).expect("serialize"));
    let _ = io::stdout().flush();
}

fn fail_value(error: impl Into<String>, hint: impl Into<String>) -> Value {
    json!({ "error": error.into(), "hint": hint.into() })
}

fn env_or(key: &str) -> String {
    env::var(key).unwrap_or_default()
}

#[derive(Debug, Clone, Default, Deserialize)]
struct BridgeConfig {
    #[serde(default)]
    cookie: String,
    #[serde(default)]
    signer_url: String,
    #[serde(default)]
    signer_token: String,
    #[serde(default)]
    device_id: String,
    #[serde(default)]
    iid: String,
    #[serde(default)]
    fp: String,
    #[serde(default)]
    quality: String,
}

impl BridgeConfig {
    fn from_env() -> Self {
        Self {
            cookie: env_or("SODA_COOKIE"),
            signer_url: env_or("QISHUI_SIGNER_URL"),
            signer_token: env_or("QISHUI_SIGNER_TOKEN"),
            device_id: env_or("SODA_DEVICE_ID"),
            iid: env_or("SODA_IID"),
            fp: env_or("SODA_FP"),
            quality: env_or("SODAM_QUALITY"),
        }
    }
}

#[derive(Debug, Deserialize)]
struct ServeRequest {
    id: u64,
    cmd: String,
    #[serde(default)]
    config: Option<BridgeConfig>,
    #[serde(default)]
    query: String,
    #[serde(default)]
    id_arg: String,
    #[serde(default)]
    out: String,
    #[serde(default)]
    token: String,
    #[serde(default)]
    liked: bool,
    #[serde(default)]
    fetch_counter: u32,
    #[serde(default)]
    did_first_use_time: u64,
    #[serde(default)]
    scene_mode_id: Option<i64>,
    #[serde(default)]
    preference_mode: String,
}

#[cfg(feature = "libresoda")]
fn make_client(cfg: &BridgeConfig) -> libresoda::Soda {
    use libresoda::soda::signature::{AppCredentials, HttpSignature};
    use libresoda::Soda;

    let soda = Soda::new(cfg.cookie.clone());
    soda.set_app_credentials(AppCredentials {
        device_id: cfg.device_id.clone(),
        iid: cfg.iid.clone(),
        fp: cfg.fp.clone(),
        ..Default::default()
    });

    let signer_url = if cfg.signer_url.trim().is_empty() {
        DEFAULT_SIGNER_URL.to_string()
    } else {
        cfg.signer_url.clone()
    };
    let signer_token = if cfg.signer_token.trim().is_empty() && signer_url.trim() == DEFAULT_SIGNER_URL
    {
        DEFAULT_SIGNER_TOKEN.to_string()
    } else {
        cfg.signer_token.clone()
    };
    if !signer_url.trim().is_empty() {
        soda.set_signature_provider(Arc::new(
            HttpSignature::new(signer_url.trim()).with_token(signer_token.trim()),
        ));
    }

    let quality = cfg.quality.trim();
    if !quality.is_empty() && quality != "auto" && quality != "best" {
        soda.set_quality_preference(quality);
    }

    #[cfg(feature = "cdp")]
    soda.enable_cdp_signer();

    soda
}

#[cfg(feature = "libresoda")]
fn song_to_track(song: &libresoda::Song) -> Value {
    let duration_ms = if song.duration > 0 {
        (song.duration as u64).saturating_mul(1000)
    } else {
        0
    };
    json!({
        "id": song.id,
        "title": song.name,
        "artist": song.artist,
        "album": song.album,
        "artist_id": song.extra_get("artist_id").unwrap_or_default(),
        "album_id": song.album_id,
        "cover": song.cover,
        "duration_ms": duration_ms,
        "is_vip": song.is_vip,
    })
}

#[cfg(feature = "libresoda")]
fn recommended_tracks(value: &Value) -> Vec<Value> {
    let Some(items) = value.get("items").and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    let mut tracks = Vec::new();
    for item in items {
        if item.get("type").and_then(|v| v.as_str()) != Some("track") {
            continue;
        }
        let Some(track) = item.pointer("/entity/track_wrapper/track") else {
            continue;
        };
        let id = track
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string();
        if id.is_empty() {
            continue;
        }
        let title = track
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("未知曲目")
            .to_string();
        let artist = track
            .get("artists")
            .and_then(|v| v.as_array())
            .map(|artists| {
                artists
                    .iter()
                    .filter_map(|a| a.get("name").and_then(|v| v.as_str()))
                    .collect::<Vec<_>>()
                    .join(" / ")
            })
            .unwrap_or_default();
        let artist_id = track
            .pointer("/artists/0/id")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        let album = track
            .pointer("/album/name")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        let album_id = track
            .pointer("/album/id")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        let duration_ms = track
            .get("duration")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0)
            .round() as u64;
        let is_vip = track
            .pointer("/label_info/only_vip_playable")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let cover = track
            .pointer("/album/url_cover")
            .and_then(|image| {
                let uri = image.get("uri")?.as_str()?;
                let template = image.get("template_prefix")?.as_str()?;
                Some(format!(
                    "https://p3-luna.douyinpic.com/img/{uri}~{template}-resize:512:512.png"
                ))
            })
            .unwrap_or_default();
        tracks.push(json!({
            "id": id,
            "title": title,
            "artist": artist,
            "album": album,
            "artist_id": artist_id,
            "album_id": album_id,
            "cover": cover,
            "duration_ms": duration_ms,
            "is_vip": is_vip,
        }));
    }
    tracks
}

#[cfg(feature = "libresoda")]
fn dispatch(soda: &libresoda::Soda, req: &ServeRequest) -> Value {
    match req.cmd.as_str() {
        "ping" => json!({ "pong": true }),
        "me" => match libresoda::soda::user_playlist::fetch_pc_me(soda) {
            Ok(me) => {
                let vip = me.my_info.is_vip
                    || matches!(
                        me.my_info.vip_stage.trim().to_ascii_lowercase().as_str(),
                        "vip" | "svip"
                    );
                let image = &me.my_info.larger_avatar_url;
                let mut avatar_url = image.urls.first().cloned().unwrap_or_default();
                if !avatar_url.is_empty() && !image.uri.is_empty() && !avatar_url.contains(&image.uri)
                {
                    avatar_url.push_str(&image.uri);
                }
                json!({
                    "nickname": me.my_info.nickname.trim(),
                    "user_id": me.my_info.id.trim(),
                    "vip": vip,
                    "avatar_url": avatar_url,
                })
            }
            Err(err) => fail_value(err.to_string(), "check SODA_COOKIE / network"),
        },
        "recommend" => {
            let fetch_counter = req.fetch_counter;
            let did_first_use_time = if req.did_first_use_time == 0 {
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_secs())
                    .unwrap_or(0)
            } else {
                req.did_first_use_time
            };
            let next_counter = fetch_counter.saturating_add(1);
            let mut body = json!({
                "played_media": [],
                "did_first_use_time": did_first_use_time,
                "is_first_request": fetch_counter == 0,
                "is_did_first_request": fetch_counter == 0,
                "feed_counts": { "mix_session_count": next_counter },
            });
            if let Some(id) = req.scene_mode_id {
                if id >= 0 {
                    body["feed_preference"] = json!({ "scene_mode_id": id });
                } else if !req.preference_mode.trim().is_empty() {
                    body["feed_preference"] =
                        json!({ "preference_mode": req.preference_mode.trim() });
                }
            } else if !req.preference_mode.trim().is_empty() {
                body["feed_preference"] = json!({ "preference_mode": req.preference_mode.trim() });
            }
            match soda.fetch_feed_song_tab(&body) {
                Ok(value) => {
                    let tracks = recommended_tracks(&value);
                    let has_more = value
                        .get("has_more")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true);
                    json!({
                        "tracks": tracks,
                        "fetch_counter": next_counter,
                        "has_more": has_more,
                        "did_first_use_time": did_first_use_time,
                    })
                }
                Err(err) => fail_value(err.to_string(), "check cookie / signer / network"),
            }
        }
        "scenes" => match soda.feed_mode() {
            Ok(mode) => {
                let mut scenes = vec![
                    json!({
                        "text": "熟悉模式",
                        "entry_type": "scene_mode",
                        "scene_mode_id": -1,
                        "sub_queue_type": "familiar",
                        "cover": "",
                    }),
                    json!({
                        "text": "新鲜模式",
                        "entry_type": "scene_mode",
                        "scene_mode_id": -1,
                        "sub_queue_type": "fresh",
                        "cover": "",
                    }),
                ];
                for block in &mode.feed_mode_block {
                    for entry in &block.feed_mode {
                        let image = &entry.url_info;
                        let uri = image.uri.trim();
                        let template = image.template_prefix.trim();
                        let cover = if !uri.is_empty() && !template.is_empty() {
                            format!(
                                "https://p3-luna.douyinpic.com/img/{uri}~{template}-resize:128:128.png"
                            )
                        } else {
                            image.urls.first().cloned().unwrap_or_default() + uri
                        };
                        scenes.push(json!({
                            "text": entry.text,
                            "entry_type": entry.entry_type,
                            "scene_mode_id": entry.entity.feed_scene_mode.scene_mode_id,
                            "sub_queue_type": entry.entity.feed_scene_mode.sub_queue_type,
                            "cover": cover,
                        }));
                    }
                }
                json!({ "scenes": scenes })
            }
            Err(err) => fail_value(err.to_string(), "check cookie / network"),
        },
        "search" => {
            if req.query.trim().is_empty() {
                return fail_value("empty_query", "search requires query");
            }
            match soda.search(&req.query) {
                Ok(songs) => json!({ "tracks": songs.iter().map(song_to_track).collect::<Vec<_>>() }),
                Err(err) => fail_value(err.to_string(), "check cookie / network / signer"),
            }
        }
        "liked" => match soda.get_user_playlists(1, 50) {
            Ok(playlists) => {
                let liked = playlists.iter().find(|playlist| {
                    playlist.name.contains("喜欢") || playlist.name.contains("收藏")
                });
                let Some(liked) = liked else {
                    return fail_value(
                        "liked_playlist_not_found",
                        "没找到「我喜欢的音乐」歌单（账号可能未登录）",
                    );
                };
                match soda.get_playlist_songs(&liked.id) {
                    Ok(songs) => json!({
                        "playlist_id": liked.id,
                        "tracks": songs.iter().map(song_to_track).collect::<Vec<_>>(),
                    }),
                    Err(err) => fail_value(err.to_string(), "读取我喜欢的音乐失败"),
                }
            }
            Err(err) => fail_value(err.to_string(), "check cookie"),
        },
        "my-playlists" => match soda.get_my_playlists("", 50) {
            Ok(page) => {
                let playlists: Vec<_> = page
                    .playlists
                    .iter()
                    .map(|p| {
                        json!({
                            "id": p.id,
                            "title": p.name,
                            "cover": p.cover,
                            "track_count": p.track_count,
                            "creator": p.creator,
                        })
                    })
                    .collect();
                json!({
                    "playlists": playlists,
                    "has_more": page.has_more,
                    "next_cursor": page.next_cursor,
                })
            }
            Err(err) => fail_value(err.to_string(), "check cookie"),
        },
        "playlist" => {
            if req.id_arg.trim().is_empty() {
                return fail_value("missing_id", "playlist requires id_arg");
            }
            match soda.get_playlist_songs(&req.id_arg) {
                Ok(songs) => json!({
                    "id": req.id_arg,
                    "tracks": songs.iter().map(song_to_track).collect::<Vec<_>>(),
                }),
                Err(err) => fail_value(err.to_string(), "check playlist id / cookie"),
            }
        }
        "lyrics" => {
            // 对齐 SodaM：回传原始增强 LRC（含逐字时间轴），由客户端 parse_lrc。
            if req.id_arg.trim().is_empty() {
                return fail_value("missing_id", "lyrics requires id_arg");
            }
            match libresoda::soda::track::fetch_web_track_v2(soda, &req.id_arg) {
                Ok(response) => json!({
                    "raw": response.lyric.content,
                    "lrc": libresoda::soda::lyric::parse_soda_lyric(&response.lyric.content),
                }),
                Err(err) => fail_value(err.to_string(), "lyrics may be empty for some tracks"),
            }
        }
        "artist" => {
            if req.id_arg.trim().is_empty() {
                return fail_value("missing_id", "artist requires id_arg");
            }
            match soda.fetch_artist_detail(&req.id_arg) {
                Ok(value) => {
                    if value
                        .get("status_code")
                        .and_then(|v| v.as_i64())
                        .unwrap_or(0)
                        != 0
                    {
                        return fail_value(
                            value
                                .pointer("/status_info/status_msg")
                                .and_then(|v| v.as_str())
                                .unwrap_or("artist error")
                                .to_string(),
                            "读取音乐人失败",
                        );
                    }
                    let info = value.get("artist_info").cloned().unwrap_or(Value::Null);
                    let avatar = info
                        .get("url_avatar")
                        .and_then(|img| {
                            let uri = img.get("uri")?.as_str()?;
                            let template = img.get("template_prefix")?.as_str().unwrap_or("");
                            if !uri.is_empty() && !template.is_empty() {
                                Some(format!(
                                    "https://p3-luna.douyinpic.com/img/{uri}~{template}-resize:300:300.png"
                                ))
                            } else {
                                img.get("urls")?
                                    .as_array()?
                                    .first()?
                                    .as_str()
                                    .map(|s| s.to_string() + uri)
                            }
                        })
                        .unwrap_or_default();
                    let mut tracks = Vec::new();
                    if let Some(arr) = value.get("hot_tracks").and_then(|v| v.as_array()) {
                        for item in arr {
                            if let Ok(track) =
                                serde_json::from_value::<libresoda::soda::types::Track>(item.clone())
                            {
                                let song = libresoda::soda::track::build_song_from_track(&track);
                                tracks.push(song_to_track(&song));
                            }
                        }
                    }
                    let mut albums = Vec::new();
                    if let Some(arr) = value.get("hot_albums").and_then(|v| v.as_array()) {
                        for item in arr {
                            let id = item
                                .get("id")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string();
                            let title = item
                                .get("name")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string();
                            let cover = item
                                .get("url_cover")
                                .and_then(|img| {
                                    let uri = img.get("uri")?.as_str()?;
                                    let template =
                                        img.get("template_prefix")?.as_str().unwrap_or("");
                                    if !uri.is_empty() && !template.is_empty() {
                                        Some(format!(
                                            "https://p3-luna.douyinpic.com/img/{uri}~{template}-resize:300:300.png"
                                        ))
                                    } else {
                                        None
                                    }
                                })
                                .unwrap_or_default();
                            let track_count = item
                                .get("count_tracks")
                                .and_then(|v| v.as_i64())
                                .unwrap_or(0);
                            if !id.is_empty() {
                                albums.push(json!({
                                    "id": id,
                                    "title": title,
                                    "cover": cover,
                                    "artist": info.get("name").and_then(|v| v.as_str()).unwrap_or(""),
                                    "track_count": track_count,
                                    "release_date": item.get("release_date").and_then(|v| v.as_i64()).unwrap_or(0),
                                    "company": item.get("company").and_then(|v| v.as_str()).unwrap_or(""),
                                }));
                            }
                        }
                    }
                    json!({
                        "artist": {
                            "id": info.get("id").and_then(|v| v.as_str()).unwrap_or(req.id_arg.as_str()),
                            "name": info.get("name").and_then(|v| v.as_str()).unwrap_or("音乐人"),
                            "avatar": avatar,
                            "track_count": info.get("count_tracks").and_then(|v| v.as_i64()).unwrap_or(0),
                            "follower_count": value.pointer("/artist_info/stats/count_collected").and_then(|v| v.as_i64()).unwrap_or(0),
                        },
                        "description": info.get("description").and_then(|v| v.as_str()).unwrap_or(""),
                        "tracks": tracks,
                        "albums": albums,
                        "tracks_has_more": value.get("has_more_tracks").and_then(|v| v.as_bool()).unwrap_or(!tracks.is_empty()),
                    })
                }
                Err(err) => fail_value(err.to_string(), "check artist id / cookie"),
            }
        }
        "album" => {
            if req.id_arg.trim().is_empty() {
                return fail_value("missing_id", "album requires id_arg");
            }
            match soda.fetch_pc_album_detail(&req.id_arg) {
                Ok(value) => {
                    if value
                        .get("status_code")
                        .and_then(|v| v.as_i64())
                        .unwrap_or(0)
                        != 0
                    {
                        return fail_value(
                            value
                                .pointer("/status_info/status_msg")
                                .and_then(|v| v.as_str())
                                .unwrap_or("album error")
                                .to_string(),
                            "读取专辑失败",
                        );
                    }
                    let info = value.get("album_info").cloned().unwrap_or(Value::Null);
                    let cover = info
                        .get("url_cover")
                        .and_then(|img| {
                            let uri = img.get("uri")?.as_str()?;
                            let template = img.get("template_prefix")?.as_str().unwrap_or("");
                            if !uri.is_empty() && !template.is_empty() {
                                Some(format!(
                                    "https://p3-luna.douyinpic.com/img/{uri}~{template}-resize:512:512.png"
                                ))
                            } else {
                                None
                            }
                        })
                        .unwrap_or_default();
                    let artist = info
                        .get("artists")
                        .and_then(|v| v.as_array())
                        .map(|artists| {
                            artists
                                .iter()
                                .filter_map(|a| a.get("name").and_then(|v| v.as_str()))
                                .collect::<Vec<_>>()
                                .join(" / ")
                        })
                        .unwrap_or_default();
                    let mut tracks = Vec::new();
                    if let Some(arr) = value.get("tracks").and_then(|v| v.as_array()) {
                        for item in arr {
                            if let Ok(track) =
                                serde_json::from_value::<libresoda::soda::types::Track>(item.clone())
                            {
                                let song = libresoda::soda::track::build_song_from_track(&track);
                                tracks.push(song_to_track(&song));
                            }
                        }
                    }
                    json!({
                        "album": {
                            "id": info.get("id").and_then(|v| v.as_str()).unwrap_or(req.id_arg.as_str()),
                            "title": info.get("name").and_then(|v| v.as_str()).unwrap_or("专辑"),
                            "cover": cover,
                            "artist": artist,
                            "track_count": info.get("count_tracks").and_then(|v| v.as_i64()).unwrap_or(tracks.len() as i64),
                            "release_date": info.get("release_date").and_then(|v| v.as_i64()).unwrap_or(0),
                            "company": info.get("company").and_then(|v| v.as_str()).unwrap_or(""),
                        },
                        "tracks": tracks,
                    })
                }
                Err(err) => fail_value(err.to_string(), "check album id / cookie"),
            }
        }
        "download" => {
            if req.id_arg.trim().is_empty() || req.out.trim().is_empty() {
                return fail_value("missing_args", "download requires id_arg and out");
            }
            let mut song = libresoda::Song::default();
            song.id = req.id_arg.clone();
            let out = PathBuf::from(&req.out);
            match soda.download_with_info(&song, &out) {
                Ok(info) => json!({
                    "ok": true,
                    "quality": info.quality,
                    "bitrate": info.bitrate,
                    "preview": info.is_preview,
                    "path": out.display().to_string(),
                }),
                Err(err) => fail_value(
                    err.to_string(),
                    "VIP full tracks need signer; free/preview may still work",
                ),
            }
        }
        "collect" | "uncollect" => {
            if req.id_arg.trim().is_empty() {
                return fail_value("missing_id", "collect requires id_arg");
            }
            let liked = req.cmd == "collect" || req.liked;
            let media = [libresoda::soda::media_ref::MediaRef::track(&req.id_arg)];
            let result = if liked {
                soda.collect_media(&media)
            } else {
                soda.uncollect_media(&media)
            };
            match result {
                Ok(_) => json!({ "ok": true, "liked": liked }),
                Err(err) => fail_value(err.to_string(), "check cookie / signer"),
            }
        }
        "qr-create" => match soda.create_qr() {
            Ok(qr) => json!({
                "token": qr.token,
                "scan_url": qr.scan_url,
                "qr_image": qr.qr_image,
                "expire_time": qr.expire_time,
            }),
            Err(err) => fail_value(
                err.to_string(),
                "QR needs Chromium/Chrome (CDP). Or paste Cookie in Settings.",
            ),
        },
        "qr-check" => {
            if req.token.trim().is_empty() {
                return fail_value("missing_token", "qr-check requires token");
            }
            match soda.check_qr(&req.token) {
                Ok(result) => {
                    let need_second_verify = result
                        .extra
                        .get("need_second_verify")
                        .map(|v| v == "true")
                        .unwrap_or(false);
                    let rate_limited = result
                        .extra
                        .get("rate_limited")
                        .map(|v| v == "true")
                        .unwrap_or(false);
                    json!({
                        "status": result.status.as_str(),
                        "message": result.message,
                        "cookie": result.cookie,
                        "need_second_verify": need_second_verify,
                        "rate_limited": rate_limited,
                    })
                }
                Err(err) => fail_value(err.to_string(), "poll again or recreate QR"),
            }
        }
        "qr-open-verify" => {
            if req.token.trim().is_empty() {
                return fail_value("missing_token", "qr-open-verify requires token");
            }
            match soda.open_second_verify(&req.token) {
                Ok(url) => json!({ "ok": true, "url": url }),
                Err(err) => fail_value(
                    err.to_string(),
                    "打开二次验证失败；可改用官方客户端导出 Cookie",
                ),
            }
        }
        other => fail_value(
            format!("unknown_command:{other}"),
            "see sodaplus-bridge serve protocol",
        ),
    }
}

#[cfg(all(feature = "libresoda", unix))]
fn kill_orphan_cdp_chrome() {
    // bridge 异常退出时 headless Chrome 可能变成孤儿，占住 Dock。
    let _ = std::process::Command::new("pkill")
        .args(["-f", "libresoda-cdp-|/LibresodaCDP.app/"])
        .status();
}

#[cfg(all(feature = "libresoda", not(unix)))]
fn kill_orphan_cdp_chrome() {}

#[cfg(feature = "libresoda")]
fn run_serve() -> ExitCode {
    kill_orphan_cdp_chrome();
    let mut cfg = BridgeConfig::from_env();
    let mut soda = make_client(&cfg);
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(line) => line,
            Err(err) => {
                eprintln!("stdin read error: {err}");
                break;
            }
        };
        if line.trim().is_empty() {
            continue;
        }
        let req: ServeRequest = match serde_json::from_str(&line) {
            Ok(req) => req,
            Err(err) => {
                print_json(&json!({
                    "id": 0,
                    "ok": false,
                    "error": format!("bad_request:{err}"),
                    "hint": "each line must be JSON ServeRequest",
                }));
                continue;
            }
        };

        if req.cmd == "configure" || req.config.is_some() {
            if let Some(next) = req.config.clone() {
                cfg = next;
                soda = make_client(&cfg);
            }
            if req.cmd == "configure" {
                print_json(&json!({ "id": req.id, "ok": true, "configured": true }));
                continue;
            }
        }

        if req.cmd == "shutdown" {
            print_json(&json!({ "id": req.id, "ok": true, "bye": true }));
            kill_orphan_cdp_chrome();
            break;
        }

        let result = dispatch(&soda, &req);
        let ok = result.get("error").is_none();
        let mut response = json!({ "id": req.id, "ok": ok });
        if let Some(obj) = response.as_object_mut() {
            if let Some(map) = result.as_object() {
                for (k, v) in map {
                    obj.insert(k.clone(), v.clone());
                }
            }
        }
        print_json(&response);
    }
    kill_orphan_cdp_chrome();
    ExitCode::SUCCESS
}

#[cfg(not(feature = "libresoda"))]
fn run_serve() -> ExitCode {
    print_json(&fail_value(
        "libresoda_not_linked",
        "Run ./scripts/fetch-libresoda.sh then rebuild bridge",
    ));
    ExitCode::from(1)
}

/// 兼容旧 CLI：一次性命令（非 QR 可用；QR 请走 serve）。
#[cfg(feature = "libresoda")]
fn run_oneshot(cmd: &str, args: &mut impl Iterator<Item = String>) -> ExitCode {
    let cfg = BridgeConfig::from_env();
    let soda = make_client(&cfg);
    let mut req = ServeRequest {
        id: 0,
        cmd: cmd.to_string(),
        config: None,
        query: String::new(),
        id_arg: String::new(),
        out: String::new(),
        token: String::new(),
        liked: false,
        fetch_counter: 0,
        did_first_use_time: 0,
        scene_mode_id: None,
        preference_mode: String::new(),
    };
    match cmd {
        "search" => req.query = args.next().unwrap_or_default(),
        "playlist" | "lyrics" | "collect" | "uncollect" | "artist" | "album" => {
            req.id_arg = args.next().unwrap_or_default();
            req.liked = cmd == "collect";
        }
        "download" => {
            while let Some(arg) = args.next() {
                match arg.as_str() {
                    "--id" => req.id_arg = args.next().unwrap_or_default(),
                    "--out" => req.out = args.next().unwrap_or_default(),
                    other if req.id_arg.is_empty() => req.id_arg = other.to_string(),
                    other if req.out.is_empty() => req.out = other.to_string(),
                    _ => {}
                }
            }
        }
        "qr-check" | "qr-open-verify" => req.token = args.next().unwrap_or_default(),
        "recommend" => {
            while let Some(arg) = args.next() {
                match arg.as_str() {
                    "--fetch-counter" => {
                        req.fetch_counter = args.next().and_then(|v| v.parse().ok()).unwrap_or(0);
                    }
                    "--did-first-use-time" => {
                        req.did_first_use_time =
                            args.next().and_then(|v| v.parse().ok()).unwrap_or(0);
                    }
                    "--scene-mode-id" => {
                        req.scene_mode_id = args.next().and_then(|v| v.parse().ok());
                    }
                    "--preference-mode" => {
                        req.preference_mode = args.next().unwrap_or_default();
                    }
                    _ => {}
                }
            }
        }
        _ => {}
    }
    let result = dispatch(&soda, &req);
    print_json(&result);
    if result.get("error").is_some() {
        ExitCode::from(1)
    } else {
        ExitCode::SUCCESS
    }
}

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    let Some(cmd) = args.next() else {
        eprintln!(
            "usage: sodaplus-bridge <serve|version|me|recommend|...> ...\n\
             QR login requires: sodaplus-bridge serve  (persistent CDP process)"
        );
        return ExitCode::from(2);
    };

    match cmd.as_str() {
        "version" => {
            print_json(&json!({
                "name": "sodaplus-bridge",
                "version": env!("CARGO_PKG_VERSION"),
                "libresoda": cfg!(feature = "libresoda"),
                "cdp": cfg!(feature = "cdp"),
                "serve": true,
            }));
            ExitCode::SUCCESS
        }
        "serve" => run_serve(),
        #[cfg(feature = "libresoda")]
        other => run_oneshot(other, &mut args),
        #[cfg(not(feature = "libresoda"))]
        _ => {
            print_json(&fail_value(
                "libresoda_not_linked",
                "Run ./scripts/fetch-libresoda.sh then rebuild bridge",
            ));
            ExitCode::from(1)
        }
    }
}
