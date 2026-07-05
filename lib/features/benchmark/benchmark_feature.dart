import 'package:flutter/material.dart';

import '../../app/di/service_locator.dart';
import 'application/relay_benchmark_runner.dart';
import 'benchmark_feature_flags.dart';
import 'application/direct_benchmark_runner.dart';
import 'presentation/pages/benchmark_page.dart';

abstract final class BenchmarkFeature {
  static const bool enabled = BenchmarkFeatureFlags.enabled;

  static Future<void> openPage(BuildContext context) {
    final DirectBenchmarkRunner directRunner = serviceLocator.directBenchmarkRunner;
    final RelayBenchmarkRunner relayRunner = serviceLocator.relayBenchmarkRunner;
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BenchmarkPage(directRunner: directRunner, relayRunner: relayRunner),
      ),
    );
  }
}
