# DiuBangNASClient

局域网 NAS 客户端（Flutter Android 应用）：支持 mDNS 服务发现、WebDAV 文件访问、媒体预览、定时备份，以及通过 NAS 中转的设备间文件互传。

**许可证：** [MIT](LICENSE) · **版本：** 1.0.1

## 功能特性

- 通过 mDNS 自动发现局域网内的 NAS 服务器
- 控制面 Basic Auth 认证；通过 WebDAV 协议进行文件读写
- 浏览、上传、下载、预览照片和视频
- 定时备份与手动备份到 NAS 服务端
- 设备间文件互传（以 NAS 服务端 为中转）

## 环境要求

- Flutter SDK，兼容 **Dart ^3.10.7**（见 `pubspec.yaml`）
- Android 工具链（本项目**目前仅支持 Android**）
- 一台兼容的 NAS 服务器（提供控制面 API 以及 WebDAV 文件访问）

## 快速开始

1. 从 GitHub 克隆仓库：

   ```bash
   git clone https://github.com/DianDanHuaJuan/DiuBangNASClient.git
   cd DiuBangNASClient
   ```

2. 安装依赖：

   ```bash
   flutter pub get
   ```

3. 构建 Debug APK（推荐）：

   ```bash
   flutter build apk --debug
   ```

   输出文件：`build/app/outputs/flutter-apk/app-debug.apk`

   如需直接在已连接的 Android 设备或模拟器上调试运行，可额外使用：

   ```bash
   flutter run
   ```

   `flutter run` 依赖 ADB 和可用设备。

## 构建发布版本

1. 如需产出可分发的正式安装包，请自行生成或使用你自己的 Android 签名密钥库，并复制 `android/key.properties.example` 为 `android/key.properties` 后填入本机配置。

2. 构建：

   ```bash
   flutter build apk --release
   ```

   如果未提供 `android/key.properties`，当前项目会回退为使用 debug 签名完成 release 构建；这只适合本地测试，不适合对外分发或上架。

   输出文件：`build/app/outputs/flutter-apk/diubang_nasclient_<版本号>.apk`（`applicationId`: `com.diubang.nasclient`）。

## 贡献

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。提交 Pull Request 前请确保 `flutter analyze` 和 `flutter test` 通过。

## 更新日志

详见 [CHANGELOG.md](CHANGELOG.md)。

## 第三方代码

- [`third_party/extended_video_player_android`](third_party/extended_video_player_android) — 内置的视频播放器插件分支（上游许可证见该目录下的 `LICENSE` 文件）。

## 安全

详见 [SECURITY.md](SECURITY.md)。切勿提交生产凭据、签名密钥库或私有签名文件。
