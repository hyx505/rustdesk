# 自用远控

适用 Windows 10/11 x64。两台电脑使用同一个安装包，可以互为主控和被控。项目基于 RustDesk 1.5.3，随源码保留 AGPLv3 许可。

## 从已有构建生成安装包

1. 使用 Git 检出 `personal/main`，在 GitHub Actions 的同一提交下下载 `PersonalRemote-windows-x64-template`。它包含程序和打包模板，服务器配置在本机打包时加入。
2. 在项目目录运行以下命令。第一条命令从当前 Windows 用户的原版 RustDesk 配置读取 ID 服务器和公钥，中继自动选择。配置保存在 Git 忽略的 `.personal-remote.json`。

   ```powershell
   python res/personal_remote.py import-config
   python -m pip install -r libs/portable/requirements.txt
   python res/personal_remote.py package "$env:USERPROFILE\Downloads\PersonalRemote-windows-x64-template.zip"
   ```

   如果用其他 Python 环境安装依赖，请用同一个环境执行打包。需要手动配置时，在项目根目录创建 `.personal-remote.json`，填写 `id_server`、`server_key` 和 `relay_server`。中继自动选择时令 `relay_server` 为空字符串。服务器密钥只填 `id_ed25519.pub` 的公钥。
3. 在 `dist/personal-remote/` 获取安装 EXE 和 SHA-256 文件。双击 EXE 打开安装界面。升级时运行新版安装包，保留上一版安装包用于手动回退。

## 在客户端检查更新

从 0.1.6 开始，在「设置 → 常规 → 检查更新」可选择本地目录、Windows 共享目录或填写 HTTPS 地址。首次从 0.1.5 升级时，双击 0.1.6 安装包覆盖安装。

后续每次发布个人版时，在`res/personal_remote.py`、`libs/portable/build.rs` 和 `flutter/lib/desktop/widgets/personal_update_feed.dart` 中同步个人版本号，再正常构建和打包。打包会生成安装 EXE、SHA-256 文件和 `update.json`。将新 EXE 放入更新目录，再更新目录里的 `update.json`。如果直接使用本机的 `dist/personal-remote/`，打包脚本会按此顺序写入。

在客户端填写该目录，或指向其 `update.json` 的 HTTPS 链接。客户端检查个人版版本和服务器配置，核对下载文件的大小与 SHA-256，再由使用者打开安装器。安装包含个人服务器配置，请将更新源放在只有你信任的发布者可写、接收者可读的位置。

## 从源码构建

Windows 构建采用上游固定版本。准备 Visual Studio 2022 C++ 构建工具、Python 3.11、Rust 1.75.0、LLVM 15.0.6、Flutter 3.24.5 和 vcpkg `9e593bb18ea69cc5095e012465dcd675a822ed0d`。按仓库的 Windows 工作流准备 Flutter x64 自定义引擎、下拉菜单补丁，并将 vcpkg 依赖安装到 `VCPKG_ROOT/installed`。在 Windows 本地构建时，工具链需要能够创建 Flutter 插件使用的符号链接。

```powershell
git submodule update --init --recursive
python res/personal_remote.py import-bridge "$env:USERPROFILE\Downloads\bridge-artifact.zip"
python res/personal_remote.py build
```

桥接 ZIP 可从同一提交的 GitHub Actions 下载。安装依赖时使用 `x64-windows-static` 作为构建和主机 triplet。GitHub 构建的模板还包含上游 Windows 隐私屏辅助组件。

## 第一次验证

- 在本机和另一台授权 Windows 电脑安装。待两台都显示连接就绪后，一台在「远程协助」复制设备 ID 和临时验证码，另一台输入设备 ID 发起连接。密码验证或来访确认应遵循被控端设置。
- 在能直连的网络建立一次会话，确认工具栏显示「直连」。再在设备菜单开启强制中继并重连，确认显示「中继」。使用测试配置核对错误公钥会阻止连接。
- 在「最近连接」收藏设备，在「收藏」页新建分组并从设备菜单移入。重启查看设备、别名和分组是否恢复。删除分组应将设备放回「未分组」。
- 在具备多屏和唤醒条件的设备上，验证切屏、分窗、隐私屏恢复、局域网唤醒。检查 125% 和 200% 显示缩放下的工具栏、全屏退出、键鼠焦点及断开操作。
- 在 Windows 的安装应用列表中查找 PersonalRemote 并卸载，验证原版 RustDesk 仍可正常打开。
