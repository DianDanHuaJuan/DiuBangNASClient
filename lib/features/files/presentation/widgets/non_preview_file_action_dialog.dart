import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/di/service_locator.dart';
import '../../../preview/application/params/save_original_to_public_storage_params.dart';
import '../../../transfer/domain/entities/transfer_status.dart';
import '../../../transfer/domain/entities/transfer_task_entity.dart';
import '../../../transfer/presentation/cubit/transfer_cubit.dart';
import '../../../transfer/presentation/cubit/transfer_state.dart';
import '../../application/params/build_file_browser_download_path_params.dart';
import '../../domain/entities/file_entry_entity.dart';
import 'non_preview_file_icon.dart';

enum NonPreviewFileDialogMode { download, delete }

enum _DownloadPhase { idle, downloading, finalizing, failed }

Future<void> showNonPreviewFileActionDialog({
  required BuildContext context,
  required FileEntryEntity file,
  required NonPreviewFileDialogMode mode,
  required String rootId,
  VoidCallback? onDeleteConfirmed,
}) {
  final transferCubit = context.read<TransferCubit>();

  return showDialog<void>(
    context: context,
    barrierDismissible: mode == NonPreviewFileDialogMode.delete,
    builder: (dialogContext) {
      return BlocProvider<TransferCubit>.value(
        value: transferCubit,
        child: NonPreviewFileActionDialog(
          file: file,
          mode: mode,
          rootId: rootId,
          onDeleteConfirmed: onDeleteConfirmed,
        ),
      );
    },
  );
}

class NonPreviewFileActionDialog extends StatefulWidget {
  final FileEntryEntity file;
  final NonPreviewFileDialogMode mode;
  final String rootId;
  final VoidCallback? onDeleteConfirmed;

  const NonPreviewFileActionDialog({
    super.key,
    required this.file,
    required this.mode,
    required this.rootId,
    this.onDeleteConfirmed,
  });

  @override
  State<NonPreviewFileActionDialog> createState() =>
      _NonPreviewFileActionDialogState();
}

class _NonPreviewFileActionDialogState extends State<NonPreviewFileActionDialog> {
  _DownloadPhase _phase = _DownloadPhase.idle;
  double _progress = 0;
  String? _taskId;
  String? _localPath;
  String? _errorMessage;
  bool _isStartingDownload = false;

  NonPreviewFileIconStyle get _iconStyle =>
      resolveNonPreviewFileIconStyle(widget.file);

  bool get _isDownloadMode => widget.mode == NonPreviewFileDialogMode.download;

  bool get _canDismiss =>
      !_isDownloadMode ||
      _phase == _DownloadPhase.idle ||
      _phase == _DownloadPhase.failed;

  @override
  Widget build(BuildContext context) {
    final dialog = Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NonPreviewFileIconPlaceholder(
              style: _iconStyle,
              showProgressRing: _isDownloadMode,
              progress: _isDownloadMode ? _progress : null,
            ),
            const SizedBox(height: 16),
            Text(
              widget.file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2F2E2B),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatNonPreviewFileSize(widget.file.size),
              style: const TextStyle(fontSize: 13, color: Color(0xFF6D6C6A)),
            ),
            if (_isDownloadMode && _phase == _DownloadPhase.finalizing) ...[
              const SizedBox(height: 8),
              const Text(
                '正在保存…',
                style: TextStyle(fontSize: 13, color: Color(0xFF3D8A5A)),
              ),
            ],
            if (_isDownloadMode &&
                _phase == _DownloadPhase.failed &&
                _errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFFB64848)),
              ),
            ],
            const SizedBox(height: 24),
            if (_isDownloadMode) ..._buildDownloadActions() else ..._buildDeleteActions(),
          ],
        ),
      ),
    );

    if (!_isDownloadMode) {
      return dialog;
    }

    return PopScope(
      canPop: _canDismiss,
      child: BlocListener<TransferCubit, TransferState>(
        listener: _handleTransferStateChanged,
        child: dialog,
      ),
    );
  }

  List<Widget> _buildDownloadActions() {
    final isBusy =
        _phase == _DownloadPhase.downloading ||
        _phase == _DownloadPhase.finalizing ||
        _isStartingDownload;

    return [
      if (_phase == _DownloadPhase.idle || _phase == _DownloadPhase.failed)
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isBusy ? null : _startDownload,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3D8A5A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              _phase == _DownloadPhase.failed
                  ? Icons.refresh_rounded
                  : Icons.download_rounded,
              size: 18,
            ),
            label: Text(_phase == _DownloadPhase.failed ? '重试' : '下载'),
          ),
        ),
      if (_phase == _DownloadPhase.idle || _phase == _DownloadPhase.failed)
        const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: _canDismiss ? () => Navigator.pop(context) : null,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF6D6C6A),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            '取消',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildDeleteActions() {
    return [
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () {
            widget.onDeleteConfirmed?.call();
            Navigator.pop(context);
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB64848),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('删除'),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF6D6C6A),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            '取消',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ),
    ];
  }

  Future<void> _startDownload() async {
    if (_isStartingDownload ||
        _phase == _DownloadPhase.downloading ||
        _phase == _DownloadPhase.finalizing) {
      return;
    }

    setState(() {
      _isStartingDownload = true;
      _errorMessage = null;
      _progress = 0;
      _taskId = null;
    });

    try {
      final localPath =
          await serviceLocator.buildFileBrowserDownloadPathUseCase.call(
            BuildFileBrowserDownloadPathParams(fileName: widget.file.name),
          );
      if (!mounted) {
        return;
      }

      final task = await context.read<TransferCubit>().enqueueDownload(
        remotePath: widget.file.path,
        localPath: localPath,
        rootId: widget.rootId,
      );
      if (!mounted) {
        return;
      }

      if (task == null) {
        setState(() {
          _isStartingDownload = false;
          _phase = _DownloadPhase.failed;
          _errorMessage = '添加下载任务失败';
        });
        return;
      }

      setState(() {
        _isStartingDownload = false;
        _phase = _DownloadPhase.downloading;
        _taskId = task.id;
        _localPath = localPath;
        _progress = task.progress;
      });
      _handleTransferStateChanged(context, context.read<TransferCubit>().state);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isStartingDownload = false;
        _phase = _DownloadPhase.failed;
        _errorMessage = '下载失败: $error';
      });
    }
  }

  void _handleTransferStateChanged(
    BuildContext context,
    TransferState transferState,
  ) {
    if (!_isDownloadMode || _taskId == null) {
      return;
    }
    if (transferState is! TransferLoaded) {
      return;
    }

    final task = _findTaskById(transferState.tasks, _taskId!);
    if (task == null) {
      return;
    }

    if (task.status == TransferStatus.failed) {
      setState(() {
        _phase = _DownloadPhase.failed;
        _errorMessage = task.errorMessage ?? '下载失败，请重试';
        _progress = 0;
      });
      return;
    }

    if (_phase == _DownloadPhase.downloading) {
      if (task.status == TransferStatus.completed) {
        setState(() {
          _phase = _DownloadPhase.finalizing;
          _progress = 1;
          _localPath = task.localPath.isNotEmpty ? task.localPath : _localPath;
        });
        unawaited(_finalizeDownload(task));
        return;
      }

      setState(() {
        _progress = task.progress;
      });
    }
  }

  Future<void> _finalizeDownload(TransferTaskEntity task) async {
    final localPath = task.localPath.isNotEmpty ? task.localPath : _localPath;
    if (localPath == null || localPath.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _DownloadPhase.failed;
        _errorMessage = '下载文件路径丢失';
      });
      return;
    }

    final result = await serviceLocator.saveOriginalToPublicStorageUseCase.call(
      SaveOriginalToPublicStorageParams(
        localPath: localPath,
        fileName: widget.file.name,
      ),
    );

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);

    result.when(
      success: (_) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '已下载: ${widget.file.name}\n已保存到 下载/NASClient',
            ),
          ),
        );
      },
      failure: (_) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '已下载: ${widget.file.name}\n保存位置: $localPath',
            ),
          ),
        );
      },
    );
  }

  TransferTaskEntity? _findTaskById(
    List<TransferTaskEntity> tasks,
    String taskId,
  ) {
    for (final task in tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }
}
