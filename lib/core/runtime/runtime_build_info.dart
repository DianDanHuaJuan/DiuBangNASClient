abstract final class RuntimeBuildInfo {
  static const String appVersion = String.fromEnvironment(
    'NAS_APP_VERSION',
    defaultValue: 'dev',
  );
  static const String buildSha = String.fromEnvironment(
    'NAS_BUILD_SHA',
    defaultValue: 'dev',
  );
  static const String buildTime = String.fromEnvironment(
    'NAS_BUILD_TIME',
    defaultValue: 'unknown',
  );

  static Map<String, String> toJson() {
    return <String, String>{
      'appVersion': appVersion,
      'buildSha': buildSha,
      'buildTime': buildTime,
    };
  }
}
