# 修复视频拖动进度条卡死 — HLS 转为 Progressive 优先

## 问题现象

时间轴长度已正常（durationMs 修复生效），但拖动进度条后视频播放卡死、一直缓冲。

客户端日志：解码器 `c2.mtk.avc.decoder` 疯狂解码（`inputFps=185, outputFps=179`）但不渲染（`renderFps=0, discardFps=179`）。

服务端日志：大量 `GET api/v1/preview/hls/asset/hls_1/segment_002XX.ts` 请求（从 segment_00209 开始快速拉取）。

## 根因分析

### 因果链

```
用户开启了 videoTranscodingEnabled 设置
    ↓
service_locator.dart:800  hlsVideoPreviewEnabled = videoTranscodingEnabled  → true
    ↓
preview_handler.dart:234  _hlsVideoPreviewEnabled && _shouldUseHlsTranscode(extension)
    ↓  (非 .mp4 扩展名 → _shouldUseHlsTranscode 返回 true)
服务端返回 strategy = 'hls'，URL = HLS manifest
    ↓
客户端 resolve_preview_video_source_use_case.dart:33  strategy: item.strategy  → hls
    ↓
media_kit 播放 HLS EVENT playlist（不支持 seek offset）
    ↓
seek 后 media_kv 从 segment_00209 开始快速拉取，但 EVENT playlist 无 #EXT-X-ENDLIST
    ↓
解码器疯狂解码追赶但不渲染 → 卡死
```

### 代码位置

| 文件 | 行号 | 问题代码 |
|------|:----:|----------|
| `D:\tmp\diubangNASServer_Android\lib\features\api\handlers\preview_handler.dart` | 234-236 | `_resolveVideoStrategy` 中 HLS 优先于 progressive |
| `D:\tmp\diubangNASServer_Windows\lib\features\api\handlers\preview_handler.dart` | 234-236 | 同上 |

### 当前 `_resolveVideoStrategy` 逻辑（问题代码）

```dart
String? _resolveVideoStrategy(String extension) {
  if (_hlsVideoPreviewEnabled && _shouldUseHlsTranscode(extension)) {
    return 'hls';           // ← HLS 优先！非 MP4 视频走 HLS
  }
  if (_progressiveVideoPreviewEnabled) {
    return 'progressive';   // ← progressive 只是第二选择
  }
  ...
}
```

## 修改方案

### 修改原则

media_kit 基于 libmpv/FFmpeg，格式兼容性远超 ExoPlayer（支持 MP4/MKV/AVI/MOV/WebM/3GP/HEVC/AV1 等全部常见格式）。之前用 HLS 转码是因为旧播放器（ExoPlayer）不支持某些格式，现在 media_kit 不需要转码，progressive + HTTP Range 即可完美播放和 seek。

### 修改内容

两个服务端的 `preview_handler.dart`，`_resolveVideoStrategy` 方法：**把 progressive 放在 HLS 前面**。

#### 安卓服务端

文件：`D:\tmp\diubangNASServer_Android\lib\features\api\handlers\preview_handler.dart`
行号：233-244

```dart
// 修改前：
String? _resolveVideoStrategy(String extension) {
  if (_hlsVideoPreviewEnabled && _shouldUseHlsTranscode(extension)) {
    return 'hls';
  }
  if (_progressiveVideoPreviewEnabled) {
    return 'progressive';
  }
  if (_transcodeVideoPreviewEnabled && _hlsVideoPreviewEnabled) {
    return 'hls';
  }
  return null;
}

// 修改后：
String? _resolveVideoStrategy(String extension) {
  // progressive 优先：media_kit/libmpv 支持绝大多数视频格式，无需 HLS 转码。
  if (_progressiveVideoPreviewEnabled) {
    return 'progressive';
  }
  // HLS 作为后备（仅 progressive 未启用时）。
  if (_hlsVideoPreviewEnabled && _shouldUseHlsTranscode(extension)) {
    return 'hls';
  }
  if (_transcodeVideoPreviewEnabled && _hlsVideoPreviewEnabled) {
    return 'hls';
  }
  return null;
}
```

#### Windows 服务端

文件：`D:\tmp\diubangNASServer_Windows\lib\features\api\handlers\preview_handler.dart`
行号：234-244

同上修改。

### 不需要改动的部分

- **客户端**：不需要改动。客户端直接使用服务端返回的 `strategy` 和 `url`（`resolve_preview_video_source_use_case.dart:33`）。服务端改为 progressive 优先后，客户端自动走 progressive。
- **`_shouldUseHlsTranscode`**：保留不动，作为 HLS 后备逻辑的条件判断。
- **服务端配置**：不需要改 `videoTranscodingEnabled` 的默认值或用户设置。只是策略优先级变了。

## 验证步骤

1. 修改两个服务端的 `_resolveVideoStrategy`
2. 重启两个服务端
3. 客户端连接服务端，播放非 MP4 视频（如 MKV）
4. 确认服务端日志显示 `GET /dav/...`（progressive）而非 `GET api/v1/preview/hls/...`
5. 拖动进度条，确认 seek 流畅无卡死
6. 确认倍速/双击快进/长按 2x 功能正常

## 风险评估

| 风险 | 概率 | 说明 |
|------|:----:|------|
| media_kit 不支持某视频格式 | 极低 | libmpv/FFmpeg 支持所有常见格式（MP4/MKV/AVI/MOV/WebM/3GP/HEVC/AV1） |
| 服务端 WebDAV Range 支持问题 | 极低 | 之前已确认两个服务端的 `get_handler.dart` 都支持 Range 请求 |
| 大文件 seek 延迟 | 低 | HTTP Range seek 是毫秒级，远优于 HLS seek-restart |
