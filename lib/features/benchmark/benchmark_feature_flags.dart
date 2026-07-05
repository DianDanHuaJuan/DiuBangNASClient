abstract final class BenchmarkFeatureFlags {
  static const bool enabled = bool.fromEnvironment(
    'NAS_ENABLE_BENCHMARK_TOOL',
    defaultValue: false,
  );
}
