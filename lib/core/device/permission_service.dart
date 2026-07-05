/// 文件输入：文件读写、相机、麦克风等系统权限请求
/// 文件职责：统一处理设备权限申请与检查
/// 文件对外接口：PermissionService
/// 文件包含：PermissionService
import 'package:permission_handler/permission_handler.dart'
    as permission_handler;

class PermissionService {
  Future<bool> requestStoragePermission() async {
    final status = await permission_handler.Permission.storage.request();
    return status.isGranted;
  }

  Future<bool> requestCameraPermission() async {
    final status = await permission_handler.Permission.camera.request();
    return status.isGranted;
  }

  Future<bool> requestMicrophonePermission() async {
    final status = await permission_handler.Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> requestNotificationPermission() async {
    final status = await permission_handler.Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> checkStoragePermission() async {
    final status = await permission_handler.Permission.storage.status;
    return status.isGranted;
  }

  Future<bool> checkCameraPermission() async {
    final status = await permission_handler.Permission.camera.status;
    return status.isGranted;
  }

  Future<bool> checkMicrophonePermission() async {
    final status = await permission_handler.Permission.microphone.status;
    return status.isGranted;
  }

  Future<bool> checkNotificationPermission() async {
    final status = await permission_handler.Permission.notification.status;
    return status.isGranted;
  }

  Future<void> openAppSettings() async {
    await permission_handler.openAppSettings();
  }

  Future<
    Map<permission_handler.Permission, permission_handler.PermissionStatus>
  >
  requestMultiplePermissions(
    List<permission_handler.Permission> permissions,
  ) async {
    return await permissions.request();
  }
}
