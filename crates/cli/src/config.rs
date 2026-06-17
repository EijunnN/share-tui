//! Persisted client configuration and relay-URL resolution.
//!
//! A small TOML file at `<OS config dir>/tcast/config.toml` lets users set the
//! relay once instead of retyping `wss://…` on every command. The relay URL is
//! resolved with this precedence (highest first):
//!
//! 1. `--relay <URL>` flag or the `TCAST_RELAY` env var (merged by clap).
//! 2. The saved config file (`tcast config set-relay …`).
//! 3. A compile-time default baked by the release build (`TCAST_DEFAULT_RELAY`).
//! 4. The built-in dev default `ws://127.0.0.1:4455`.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

/// Local/dev fallback used when nothing else is configured.
const DEV_RELAY: &str = "ws://127.0.0.1:4455";

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Config {
    /// Saved default relay base URL (ws:// or wss://).
    pub relay: Option<String>,
    /// Default display name for `tcast stream`.
    pub name: Option<String>,
    /// Saved host auth key (a shared secret, not a password).
    pub auth_key: Option<String>,
}

/// The config file location: `<OS config dir>/tcast/config.toml`, or the
/// explicit override when `--config` is given. `None` only if the OS exposes
/// no config directory at all.
pub fn config_path(override_path: Option<PathBuf>) -> Option<PathBuf> {
    if let Some(p) = override_path {
        return Some(p);
    }
    dirs::config_dir().map(|d| d.join("tcast").join("config.toml"))
}

/// Load config from disk. A missing or unreadable file yields defaults rather
/// than an error, so a fresh install just works.
pub fn load(path: &Path) -> Config {
    match std::fs::read_to_string(path) {
        Ok(s) => toml::from_str(&s).unwrap_or_default(),
        Err(_) => Config::default(),
    }
}

/// Write config to disk, creating the parent directory if needed.
pub fn save(path: &Path, cfg: &Config) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating config dir {}", parent.display()))?;
    }
    let s = toml::to_string_pretty(cfg).context("serializing config")?;
    std::fs::write(path, s).with_context(|| format!("writing {}", path.display()))?;
    Ok(())
}

/// Compile-time baked default relay, set by the release build via the
/// `TCAST_DEFAULT_RELAY` env var. `None` for a plain `cargo build`.
fn baked_default_relay() -> Option<&'static str> {
    // An empty value (e.g. CI expanding an undefined repo variable) counts as
    // "not baked" so it never resolves to an empty relay URL.
    match option_env!("TCAST_DEFAULT_RELAY") {
        Some(s) if !s.is_empty() => Some(s),
        _ => None,
    }
}

/// Resolve the effective relay URL given the (already clap-merged) flag/env
/// value and the loaded config.
pub fn resolve_relay(flag_or_env: Option<String>, cfg: &Config) -> String {
    flag_or_env
        .or_else(|| cfg.relay.clone())
        .or_else(|| baked_default_relay().map(str::to_string))
        .unwrap_or_else(|| DEV_RELAY.to_string())
}

/// Human-readable origin of the resolved relay, for `tcast config show`.
pub fn relay_source(flag_or_env: Option<&str>, cfg: &Config) -> &'static str {
    if flag_or_env.is_some() {
        "flag/env (--relay / TCAST_RELAY)"
    } else if cfg.relay.is_some() {
        "config file"
    } else if baked_default_relay().is_some() {
        "compile-time default"
    } else {
        "built-in dev default"
    }
}
