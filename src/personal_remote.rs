use base::config::keys;
use hbb_common::{anyhow::Context, bail, config, ResultType};

pub(crate) const PROFILE_NAME: &str = "PersonalRemote.server.json";

#[derive(serde::Deserialize)]
struct ServerProfile {
    id_server: String,
    #[serde(default)]
    relay_server: String,
    server_key: String,
}

pub(crate) fn configure() -> ResultType<()> {
    let path = std::env::current_exe()?.with_file_name(PROFILE_NAME);
    let profile: ServerProfile = serde_json::from_slice(
        &std::fs::read(path).context("缺少服务器配置，请使用本地打包的自用远控安装程序。")?,
    )
    .context("服务器配置格式无效。")?;
    if profile.id_server.trim().is_empty() || crate::get_rs_pk(&profile.server_key).is_none() {
        bail!("请检查 ID 服务器地址和服务器公钥。");
    }

    *config::APP_NAME.write().unwrap() = "PersonalRemote".to_owned();
    config::OVERWRITE_LOCAL_SETTINGS
        .write()
        .unwrap()
        .insert(keys::OPTION_ENABLE_CHECK_UPDATE.into(), "N".into());

    let mut overrides = config::OVERWRITE_SETTINGS.write().unwrap();
    overrides.insert(keys::OPTION_ALLOW_AUTO_UPDATE.into(), "N".into());
    overrides.insert(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER.into(), profile.id_server);
    overrides.insert(keys::OPTION_KEY.into(), profile.server_key);
    overrides.insert(keys::OPTION_RELAY_SERVER.into(), profile.relay_server);
    drop(overrides);

    let mut display = config::DEFAULT_DISPLAY_SETTINGS.write().unwrap();
    display.insert(keys::OPTION_SHOW_MONITORS_TOOLBAR.into(), "Y".into());
    Ok(())
}
