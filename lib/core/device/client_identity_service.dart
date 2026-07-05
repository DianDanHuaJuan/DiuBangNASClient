/// 文件输入：设备信息、安装实例标识、本地缓存
/// 文件职责：生成并维护客户端设备唯一标识
/// 文件对外接口：ClientIdentityService
/// 文件包含：ClientIdentityService
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_id_normalizer.dart';

class ClientDeviceDetails {
  const ClientDeviceDetails({
    required this.name,
    required this.type,
    this.brand,
    this.model,
  });

  final String name;
  final String type;
  final String? brand;
  final String? model;
}

class ClientIdentityService {
  static const _keyDeviceId = 'client_device_id';
  static const MethodChannel _deviceIdentityChannel = MethodChannel(
    'com.nasclient/device_identity',
  );
  final SharedPreferences _prefs;
  final DeviceInfoPlugin _deviceInfo;
  final Future<String?> Function()? _androidIdResolver;
  final bool Function()? _isAndroidPlatform;
  final bool Function()? _isIosPlatform;
  String? _cachedId;
  ClientDeviceDetails? _cachedDetails;

  ClientIdentityService({
    required SharedPreferences prefs,
    DeviceInfoPlugin? deviceInfo,
    Future<String?> Function()? androidIdResolver,
    bool Function()? isAndroidPlatform,
    bool Function()? isIosPlatform,
  }) : _prefs = prefs,
       _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _androidIdResolver = androidIdResolver,
       _isAndroidPlatform = isAndroidPlatform,
       _isIosPlatform = isIosPlatform;

  Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;

    final deviceId = DeviceIdNormalizer.normalizeRequired(
      await _resolvePreferredDeviceId(),
    );
    if (_prefs.getString(_keyDeviceId) != deviceId) {
      await _prefs.setString(_keyDeviceId, deviceId);
    }
    _cachedId = deviceId;
    return deviceId;
  }

  Future<String> _resolvePreferredDeviceId() async {
    if (_isRunningOnAndroid()) {
      final androidId = await _resolveAndroidId();
      if (androidId != null && androidId.isNotEmpty) {
        await _prefs.setString(_keyDeviceId, androidId);
        return androidId;
      }
      throw StateError(
        'ANDROID_ID is required on Android platform but unavailable',
      );
    }

    if (_isRunningOnIos()) {
      final idfv = await _resolveIdfv();
      if (idfv != null && idfv.isNotEmpty) {
        await _prefs.setString(_keyDeviceId, idfv);
        return idfv;
      }
      throw StateError(
        'IDFV is required on iOS platform but unavailable',
      );
    }

    throw UnsupportedError(
      'Unsupported platform. Only Android and iOS are supported.',
    );
  }

  bool _isRunningOnAndroid() {
    if (_isAndroidPlatform != null) {
      return _isAndroidPlatform();
    }
    return !kIsWeb && Platform.isAndroid;
  }

  bool _isRunningOnIos() {
    if (_isIosPlatform != null) {
      return _isIosPlatform();
    }
    return !kIsWeb && Platform.isIOS;
  }

  Future<String?> _resolveAndroidId() async {
    try {
      final androidId =
          await (_androidIdResolver?.call() ??
              _deviceIdentityChannel.invokeMethod<String>('getAndroidId'));
      final normalized = androidId?.trim().toLowerCase();
      if (normalized == null || normalized.isEmpty) {
        return null;
      }
      return DeviceIdNormalizer.normalize(normalized);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<String?> _resolveIdfv() async {
    try {
      final iosInfo = await _deviceInfo.iosInfo;
      final idfv = iosInfo.identifierForVendor?.trim();
      if (idfv == null || idfv.isEmpty) {
        return null;
      }
      return DeviceIdNormalizer.normalize(idfv);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<String> getDeviceName() async {
    return (await getDeviceDetails()).name;
  }

  Future<String> getDeviceType() async {
    return (await getDeviceDetails()).type;
  }

  Future<String?> getDeviceBrand() async {
    return (await getDeviceDetails()).brand;
  }

  Future<String?> getDeviceModel() async {
    return (await getDeviceDetails()).model;
  }

  Future<ClientDeviceDetails> getDeviceDetails() async {
    final cachedDetails = _cachedDetails;
    if (cachedDetails != null) {
      return cachedDetails;
    }

    final details = await _buildDeviceDetails();
    _cachedDetails = details;
    return details;
  }

  Future<ClientDeviceDetails> _buildDeviceDetails() async {
    final deviceInfo = _deviceInfo;

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return ClientDeviceDetails(
        name: '${androidInfo.manufacturer} ${androidInfo.model}',
        type: 'android',
        brand: androidInfo.manufacturer,
        model: androidInfo.model,
      );
    }
    if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return ClientDeviceDetails(
        name: iosInfo.utsname.machine,
        type: 'ios',
        brand: 'Apple',
        model: iosInfo.utsname.machine,
      );
    }

    throw UnsupportedError(
      'Unsupported platform. Only Android and iOS are supported.',
    );
  }
}
