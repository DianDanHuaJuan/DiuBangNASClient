import 'package:flutter/material.dart';

import '../../../../core/network/dio_path_download_service.dart';
import '../../application/direct_benchmark_runner.dart';
import '../../application/relay_benchmark_runner.dart';
import '../../domain/benchmark_models.dart';

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({
    super.key,
    required this.directRunner,
    required this.relayRunner,
  });

  final DirectBenchmarkRunner directRunner;
  final RelayBenchmarkRunner relayRunner;

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  final TextEditingController _sizeMbController = TextEditingController(
    text: '32',
  );
  final TextEditingController _relayPeerClientIdController =
      TextEditingController();
  final TextEditingController _downloadConcurrencyController =
      TextEditingController(
        text: '${PathDownloadStrategy.defaultPreferredConcurrentRequests}',
      );
  final TextEditingController
  _downloadChunkSizeMbController = TextEditingController(
    text:
        '${PathDownloadStrategy.defaultInitialChunkSizeBytes ~/ (1024 * 1024)}',
  );
  final TextEditingController
  _downloadMinChunkSizeMbController = TextEditingController(
    text:
        '${PathDownloadStrategy.defaultMinimumChunkSizeBytes ~/ (1024 * 1024)}',
  );
  final TextEditingController _downloadStallTimeoutSecondsController =
      TextEditingController(
        text: '${PathDownloadStrategy.defaultStallTimeout.inSeconds}',
      );
  final List<String> _logs = <String>[];

  BenchmarkTransferMode _mode = BenchmarkTransferMode.upload;
  BenchmarkTransportType _transportType = BenchmarkTransportType.direct;
  bool _saveDownloadToPublicStorage = false;
  bool _keepTemporaryFile = false;
  bool _isRunning = false;
  double _progress = 0;
  BenchmarkRunResult? _lastResult;
  String? _errorMessage;

  int get _recommendedInitialChunkSizeMb {
    final chunkSizeBytes = _transportType == BenchmarkTransportType.relay
        ? PathDownloadStrategy.relayDownloadDefault.initialChunkSizeBytes
        : PathDownloadStrategy.directDownloadDefault.initialChunkSizeBytes;
    return chunkSizeBytes ~/ (1024 * 1024);
  }

  @override
  void dispose() {
    _sizeMbController.dispose();
    _relayPeerClientIdController.dispose();
    _downloadConcurrencyController.dispose();
    _downloadChunkSizeMbController.dispose();
    _downloadMinChunkSizeMbController.dispose();
    _downloadStallTimeoutSecondsController.dispose();
    super.dispose();
  }

  Future<void> _runBenchmark() async {
    final sizeMb = int.tryParse(_sizeMbController.text.trim());
    final requiresFileSize =
        !(_transportType == BenchmarkTransportType.relay &&
            _mode == BenchmarkTransferMode.download);
    final downloadConcurrency = int.tryParse(
      _downloadConcurrencyController.text.trim(),
    );
    final downloadChunkSizeMb = int.tryParse(
      _downloadChunkSizeMbController.text.trim(),
    );
    final downloadMinChunkSizeMb = int.tryParse(
      _downloadMinChunkSizeMbController.text.trim(),
    );
    final downloadStallTimeoutSeconds = int.tryParse(
      _downloadStallTimeoutSecondsController.text.trim(),
    );
    if (requiresFileSize && (sizeMb == null || sizeMb <= 0)) {
      setState(() {
        _errorMessage = '请输入有效的文件大小（MB）';
      });
      return;
    }
    if (_mode == BenchmarkTransferMode.download) {
      if (downloadConcurrency == null || downloadConcurrency <= 0) {
        setState(() {
          _errorMessage = '请输入有效的下载并发路数';
        });
        return;
      }
      if (downloadChunkSizeMb == null || downloadChunkSizeMb <= 0) {
        setState(() {
          _errorMessage = '请输入有效的初始分块大小（MB）';
        });
        return;
      }
      if (downloadMinChunkSizeMb == null || downloadMinChunkSizeMb <= 0) {
        setState(() {
          _errorMessage = '请输入有效的最小分块大小（MB）';
        });
        return;
      }
      if (downloadChunkSizeMb < downloadMinChunkSizeMb) {
        setState(() {
          _errorMessage = '初始分块大小不能小于最小分块大小';
        });
        return;
      }
      if (downloadStallTimeoutSeconds == null ||
          downloadStallTimeoutSeconds <= 0) {
        setState(() {
          _errorMessage = '请输入有效的 stalled 判定超时（秒）';
        });
        return;
      }
    }

    final options = BenchmarkExecutionOptions(
      fileSizeBytes: (sizeMb == null || sizeMb <= 0) ? 0 : sizeMb * 1024 * 1024,
      mode: _mode,
      transportType: _transportType,
      saveDownloadToPublicStorage:
          _mode == BenchmarkTransferMode.download &&
          _saveDownloadToPublicStorage,
      keepTemporaryFile: _keepTemporaryFile,
      relayPeerClientId: _relayPeerClientIdController.text,
      downloadConcurrency:
          downloadConcurrency ??
          PathDownloadStrategy.defaultPreferredConcurrentRequests,
      downloadInitialChunkSizeBytes:
          (downloadChunkSizeMb ??
              (PathDownloadStrategy.defaultInitialChunkSizeBytes ~/
                  (1024 * 1024))) *
          1024 *
          1024,
      downloadMinimumChunkSizeBytes:
          (downloadMinChunkSizeMb ??
              (PathDownloadStrategy.defaultMinimumChunkSizeBytes ~/
                  (1024 * 1024))) *
          1024 *
          1024,
      downloadStallTimeout: Duration(
        seconds:
            downloadStallTimeoutSeconds ??
            PathDownloadStrategy.defaultStallTimeout.inSeconds,
      ),
    );
    final sizeLabel = requiresFileSize ? '${sizeMb}MB' : 'history-selected';

    setState(() {
      _isRunning = true;
      _progress = 0;
      _logs
        ..clear()
        ..add('Benchmark started: ${_mode.name} $sizeLabel')
        ..add(
          'Download strategy: ${options.downloadConcurrency}x, '
          '${options.downloadInitialChunkSizeBytes ~/ (1024 * 1024)}MB init, '
          '${options.downloadMinimumChunkSizeBytes ~/ (1024 * 1024)}MB min, '
          '${options.downloadStallTimeout.inSeconds}s stall',
        );
      _lastResult = null;
      _errorMessage = null;
    });

    try {
      final result = await (_transportType != BenchmarkTransportType.relay
          ? widget.directRunner.run(
              options: options,
              onProgress: (progress) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _progress = progress;
                });
              },
              onLog: (message) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _logs.insert(0, message);
                  if (_logs.length > 200) {
                    _logs.removeRange(200, _logs.length);
                  }
                });
              },
            )
          : widget.relayRunner.run(
              options: options,
              onProgress: (progress) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _progress = progress;
                });
              },
              onLog: (message) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _logs.insert(0, message);
                  if (_logs.length > 200) {
                    _logs.removeRange(200, _logs.length);
                  }
                });
              },
            ));
      if (!mounted) {
        return;
      }
      setState(() {
        _lastResult = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('传输测速')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '独立 benchmark 模块（仅开发/诊断构建可见）',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (!(_transportType == BenchmarkTransportType.relay &&
              _mode == BenchmarkTransferMode.download))
            TextField(
              controller: _sizeMbController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '测试文件大小（MB）',
                border: OutlineInputBorder(),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'Relay 下载测速会直接下载当前可下载列表中的第一条记录，不需要手动输入 transferId 或文件大小。',
              ),
            ),
          const SizedBox(height: 12),
          SegmentedButton<BenchmarkTransportType>(
            segments: const [
              ButtonSegment(
                value: BenchmarkTransportType.direct,
                label: Text('Direct'),
                icon: Icon(Icons.compare_arrows_rounded),
              ),
              ButtonSegment(
                value: BenchmarkTransportType.directDav,
                label: Text('Direct /dav'),
                icon: Icon(Icons.folder_shared_rounded),
              ),
              ButtonSegment(
                value: BenchmarkTransportType.directHttp,
                label: Text('Direct HTTP'),
                icon: Icon(Icons.wifi_rounded),
              ),
              ButtonSegment(
                value: BenchmarkTransportType.directDavHttp,
                label: Text('/dav HTTP'),
                icon: Icon(Icons.folder_open_rounded),
              ),
              ButtonSegment(
                value: BenchmarkTransportType.relay,
                label: Text('Relay'),
                icon: Icon(Icons.hub_rounded),
              ),
            ],
            selected: <BenchmarkTransportType>{_transportType},
            onSelectionChanged: _isRunning
                ? null
                : (selection) {
                    setState(() {
                      _transportType = selection.first;
                      _downloadChunkSizeMbController.text =
                          '$_recommendedInitialChunkSizeMb';
                    });
                  },
          ),
          const SizedBox(height: 12),
          SegmentedButton<BenchmarkTransferMode>(
            segments: const [
              ButtonSegment(
                value: BenchmarkTransferMode.upload,
                label: Text('上传'),
                icon: Icon(Icons.upload_rounded),
              ),
              ButtonSegment(
                value: BenchmarkTransferMode.download,
                label: Text('下载'),
                icon: Icon(Icons.download_rounded),
              ),
            ],
            selected: <BenchmarkTransferMode>{_mode},
            onSelectionChanged: _isRunning
                ? null
                : (selection) {
                    setState(() {
                      _mode = selection.first;
                    });
                  },
          ),
          const SizedBox(height: 12),
          if (_transportType == BenchmarkTransportType.relay) ...[
            TextField(
              controller: _relayPeerClientIdController,
              enabled: !_isRunning,
              decoration: InputDecoration(
                labelText: _mode == BenchmarkTransferMode.upload
                  ? 'Relay 目标 deviceId'
                  : 'Relay 对端 deviceId（可选）',
                border: const OutlineInputBorder(),
                helperText: _mode == BenchmarkTransferMode.upload
                    ? '发送端测速必填，用于指定接收设备'
                    : '下载时可选，仅用于按发送端过滤；留空时直接取可下载列表第一条',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_mode == BenchmarkTransferMode.download) ...[
            TextField(
              controller: _downloadConcurrencyController,
              enabled: !_isRunning,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Range 并发路数',
                helperText: '推荐 2~4 路',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _downloadChunkSizeMbController,
              enabled: !_isRunning,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '初始分块大小（MB）',
                helperText: '推荐先测 16 / 24 / 32',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _downloadMinChunkSizeMbController,
              enabled: !_isRunning,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '最小分块大小（MB）',
                helperText: '建议 4 / 8 MB',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _downloadStallTimeoutSecondsController,
              enabled: !_isRunning,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'stalled 判定超时（秒）',
                helperText: '某路超时后会切分或重分配剩余任务',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SwitchListTile(
            title: const Text('保留临时文件'),
            subtitle: const Text('方便后续手动检查下载结果或生成文件'),
            value: _keepTemporaryFile,
            onChanged: _isRunning
                ? null
                : (value) {
                    setState(() {
                      _keepTemporaryFile = value;
                    });
                  },
          ),
          if (_mode == BenchmarkTransferMode.download)
            SwitchListTile(
              title: const Text('下载后保存到公共目录'),
              subtitle: const Text('开启后会把保存耗时也纳入统计'),
              value: _saveDownloadToPublicStorage,
              onChanged: _isRunning
                  ? null
                  : (value) {
                      setState(() {
                        _saveDownloadToPublicStorage = value;
                      });
                    },
            ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _isRunning ? _progress : null),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isRunning ? null : _runBenchmark,
            icon: const Icon(Icons.speed_rounded),
            label: Text(_isRunning ? '测速进行中…' : '一键开始测速'),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_lastResult != null) ...[
            const SizedBox(height: 24),
            Text('结果摘要', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _SummaryCard(result: _lastResult!),
            const SizedBox(height: 16),
            Text('原始 JSON', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(_lastResult!.prettyJson),
            ),
          ],
          const SizedBox(height: 24),
          Text('运行日志', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 120),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _logs.isEmpty
                ? const Text('暂无日志')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _logs
                        .map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(line),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.result});

  final BenchmarkRunResult result;

  String _formatDouble(dynamic value) {
    if (value is num) {
      return value.toStringAsFixed(2);
    }
    return '${value ?? '-'}';
  }

  String _formatChunkSize(dynamic value) {
    if (value is! num) {
      return '${value ?? '-'}';
    }
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final relayBenchmark = _normalizeMap(result.rawResult['relayBenchmark']);
    if (relayBenchmark != null) {
      return _buildRelaySummary(relayBenchmark);
    }

    final session = result.rawResult['session'];
    final sessionMap = _normalizeMap(session) ?? const <String, dynamic>{};
    final serverMetricsMap =
        _normalizeMap(sessionMap['serverMetrics']) ?? const <String, dynamic>{};
    final clientReportMap =
        _normalizeMap(sessionMap['clientReport']) ?? const <String, dynamic>{};
    final downloadDiagnostics =
        _normalizeMap(clientReportMap['downloadDiagnostics']) ??
        const <String, dynamic>{};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('traceId: ${sessionMap['traceId'] ?? '-'}'),
            Text('模式: ${sessionMap['mode'] ?? '-'}'),
            Text('文件大小: ${sessionMap['fileSizeBytes'] ?? '-'} bytes'),
            Text('服务端耗时: ${serverMetricsMap['elapsedMs'] ?? '-'} ms'),
            Text(
              '服务端平均吞吐: ${_formatDouble(serverMetricsMap['averageMBps'])} MB/s',
            ),
            Text('客户端总耗时: ${clientReportMap['totalMs'] ?? '-'} ms'),
            if (clientReportMap['downloadNetworkMs'] != null)
              Text('客户端下载网络耗时: ${clientReportMap['downloadNetworkMs']} ms'),
            if (downloadDiagnostics['networkReceiveMs'] != null)
              Text('网络接收耗时: ${downloadDiagnostics['networkReceiveMs']} ms'),
            if (downloadDiagnostics['localWriteMs'] != null)
              Text('本地写盘耗时: ${downloadDiagnostics['localWriteMs']} ms'),
            if (downloadDiagnostics['flushCount'] != null)
              Text(
                '写盘 flush: ${downloadDiagnostics['flushCount']} 次 / ${downloadDiagnostics['flushWriteMs'] ?? '-'} ms',
              ),
            if (downloadDiagnostics['configuredConcurrency'] != null)
              Text(
                'Range 并发: ${downloadDiagnostics['configuredConcurrency']} 配置 / ${downloadDiagnostics['effectiveConcurrency'] ?? '-'} 实际',
              ),
            if (downloadDiagnostics['initialChunkSizeBytes'] != null)
              Text(
                '分块: ${_formatChunkSize(downloadDiagnostics['initialChunkSizeBytes'])} 初始 / ${_formatChunkSize(downloadDiagnostics['minimumChunkSizeBytes'])} 最小',
              ),
            if (downloadDiagnostics['rangeRequestCount'] != null)
              Text('Range 请求数: ${downloadDiagnostics['rangeRequestCount']}'),
            if (downloadDiagnostics['stallCount'] != null)
              Text(
                'slow / stalled / split / requeue / steal / retry: ${downloadDiagnostics['slowRangeCount'] ?? '-'} / ${downloadDiagnostics['stallCount']} / ${downloadDiagnostics['splitCount'] ?? '-'} / ${downloadDiagnostics['requeueCount'] ?? '-'} / ${downloadDiagnostics['stealCount'] ?? '-'} / ${downloadDiagnostics['retryCount'] ?? '-'}',
              ),
            if (clientReportMap['saveToPublicStorageMs'] != null)
              Text('保存到公共目录耗时: ${clientReportMap['saveToPublicStorageMs']} ms'),
            if (result.temporaryFilePath != null)
              Text('临时文件: ${result.temporaryFilePath}'),
            if (result.publicUri != null) Text('公共目录 URI: ${result.publicUri}'),
          ],
        ),
      ),
    );
  }

  Widget _buildRelaySummary(Map<String, dynamic> relayBenchmark) {
    final phaseMetrics =
        _normalizeMap(relayBenchmark['phaseMetrics']) ??
        const <String, dynamic>{};
    final downloadDiagnostics =
        _normalizeMap(relayBenchmark['downloadDiagnostics']) ??
        const <String, dynamic>{};
    final finalTransfer =
        _normalizeMap(relayBenchmark['finalTransfer']) ??
        _normalizeMap(relayBenchmark['transfer']) ??
        _normalizeMap(relayBenchmark['selectedTransfer']) ??
        const <String, dynamic>{};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('角色: ${relayBenchmark['role'] ?? '-'}'),
            Text('transferId: ${relayBenchmark['transferId'] ?? '-'}'),
            Text('对端 deviceId: ${relayBenchmark['peerClientId'] ?? '-'}'),
            Text('传输状态: ${finalTransfer['status'] ?? '-'}'),
            Text('文件大小: ${finalTransfer['fileSize'] ?? '-'} bytes'),
            if (phaseMetrics['fileGenerationMs'] != null)
              Text('文件生成: ${phaseMetrics['fileGenerationMs']} ms'),
            if (phaseMetrics['createTransferMs'] != null)
              Text('创建传输: ${phaseMetrics['createTransferMs']} ms'),
            if (phaseMetrics['uploadToReadyMs'] != null)
              Text('上传到 ready: ${phaseMetrics['uploadToReadyMs']} ms'),
            if (phaseMetrics['downloadNetworkMs'] != null)
              Text('网络下载到临时文件: ${phaseMetrics['downloadNetworkMs']} ms'),
            if (downloadDiagnostics['networkReceiveMs'] != null)
              Text('网络接收耗时: ${downloadDiagnostics['networkReceiveMs']} ms'),
            if (downloadDiagnostics['localWriteMs'] != null)
              Text('本地写盘耗时: ${downloadDiagnostics['localWriteMs']} ms'),
            if (downloadDiagnostics['flushCount'] != null)
              Text(
                '写盘 flush: ${downloadDiagnostics['flushCount']} 次 / ${downloadDiagnostics['flushWriteMs'] ?? '-'} ms',
              ),
            if (downloadDiagnostics['configuredConcurrency'] != null)
              Text(
                'Range 并发: ${downloadDiagnostics['configuredConcurrency']} 配置 / ${downloadDiagnostics['effectiveConcurrency'] ?? '-'} 实际',
              ),
            if (downloadDiagnostics['initialChunkSizeBytes'] != null)
              Text(
                '分块: ${_formatChunkSize(downloadDiagnostics['initialChunkSizeBytes'])} 初始 / ${_formatChunkSize(downloadDiagnostics['minimumChunkSizeBytes'])} 最小',
              ),
            if (downloadDiagnostics['rangeRequestCount'] != null)
              Text('Range 请求数: ${downloadDiagnostics['rangeRequestCount']}'),
            if (downloadDiagnostics['stallCount'] != null)
              Text(
                'slow / stalled / split / requeue / steal / retry: ${downloadDiagnostics['slowRangeCount'] ?? '-'} / ${downloadDiagnostics['stallCount']} / ${downloadDiagnostics['splitCount'] ?? '-'} / ${downloadDiagnostics['requeueCount'] ?? '-'} / ${downloadDiagnostics['stealCount'] ?? '-'} / ${downloadDiagnostics['retryCount'] ?? '-'}',
              ),
            if (phaseMetrics['acknowledgeMs'] != null)
              Text('ack / completion API: ${phaseMetrics['acknowledgeMs']} ms'),
            if (phaseMetrics['saveToPublicStorageMs'] != null)
              Text('保存到公共目录: ${phaseMetrics['saveToPublicStorageMs']} ms'),
            if (phaseMetrics['completionAfterSaveMs'] != null)
              Text('保存后服务端完成等待: ${phaseMetrics['completionAfterSaveMs']} ms'),
            if (phaseMetrics['userVisibleMs'] != null)
              Text('用户可见完成耗时: ${phaseMetrics['userVisibleMs']} ms'),
            if (phaseMetrics['totalMs'] != null)
              Text('总耗时: ${phaseMetrics['totalMs']} ms'),
            if (relayBenchmark['usedConcurrentRanges'] != null)
              Text('并发 Range 下载: ${relayBenchmark['usedConcurrentRanges']}'),
            if (result.temporaryFilePath != null)
              Text('临时文件: ${result.temporaryFilePath}'),
            if (result.publicUri != null) Text('公共目录 URI: ${result.publicUri}'),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic>? _normalizeMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, entryValue) => MapEntry('$key', entryValue));
    }
    return null;
  }
}
