import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../core/path/nas_path.dart';
import '../../../../core/session/current_session.dart';
import '../../../transfer/domain/entities/transfer_direction.dart';
import '../../../transfer/domain/entities/transfer_status.dart';
import '../../../transfer/domain/entities/transfer_task_entity.dart';
import '../../../transfer/presentation/cubit/transfer_cubit.dart';
import '../../../transfer/presentation/cubit/transfer_state.dart';
import '../../../transfer/presentation/utils/queue_upload_to_server_directory.dart';
import '../../../transfer/presentation/widgets/upload_conflict_dialog.dart';
import '../widgets/partner_conversation_page.dart';
import '../widgets/partner_message_content.dart';

class ServerTransferChatPage extends StatefulWidget {
  const ServerTransferChatPage({super.key});

  @override
  State<ServerTransferChatPage> createState() => _ServerTransferChatPageState();
}

class _ServerTransferChatPageState extends State<ServerTransferChatPage> {
  static const QueueUploadToServerDirectory _queueUploadToServerDirectory =
      QueueUploadToServerDirectory();

  final Set<String> _trackedUploadTaskIds = <String>{};
  String? _activeConflictTaskId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<TransferCubit>().loadTasks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentSession = serviceLocator.currentSession;
    final currentServer = serviceLocator.unifiedNodeStore.currentServer;
    final target = _resolveTarget(currentSession: currentSession);

    return BlocListener<TransferCubit, TransferState>(
      listener: (context, state) {
        if (state is TransferError) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.message)));
          return;
        }
        if (state is TransferLoaded) {
          _handleTransferStateChanged(state);
        }
      },
      child: BlocBuilder<TransferCubit, TransferState>(
        builder: (context, state) {
          final tasks = state is TransferLoaded
              ? state.tasks
              : const <TransferTaskEntity>[];

          return PartnerConversationPage(
            title: _serverTitle(currentServer?.identity.displayName),
            hintMessage: target.writable
                ? '当前复用服务器资源目录传输链路，默认目标目录：${target.directoryLabel}'
                : '当前目录为只读目录，暂不支持向 ${target.directoryLabel} 上传文件。',
            isLoading: state is TransferLoading,
            messages: tasks
                .map(
                  (task) => _buildMessage(
                    task: task,
                    transferCubit: context.read<TransferCubit>(),
                  ),
                )
                .toList(growable: false),
            onRefresh: () => context.read<TransferCubit>().loadTasks(),
            emptyTitle: '还没有服务器传输记录',
            emptyDescription:
                '这里会按类聊天方式显示你和当前服务器之间的上传、下载任务；底部按钮发送的文件仍走资源目录同一套传输链路。',
            sendButtonLabel: target.writable ? '发送文件' : '当前目录不支持上传',
            onSend: target.writable
                ? () => _pickAndUpload(context, target)
                : null,
          );
        },
      ),
    );
  }

  Future<void> _pickAndUpload(
    BuildContext context,
    _ServerTransferTarget target,
  ) async {
    try {
      final result = await _queueUploadToServerDirectory(
        context,
        transferCubit: context.read<TransferCubit>(),
        targetPath: target.path,
      );
      if (!context.mounted || result == null) {
        return;
      }

      _trackedUploadTaskIds.addAll(result.createdTasks.map((task) => task.id));
      _handleTransferStateChanged(context.read<TransferCubit>().state);
      showQueuedUploadResultSnackBar(context, result: result);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('加入上传队列失败: $error')));
    }
  }

  void _handleTransferStateChanged(TransferState state) {
    if (state is! TransferLoaded || _trackedUploadTaskIds.isEmpty) {
      return;
    }

    for (final taskId in _trackedUploadTaskIds.toList(growable: false)) {
      final task = _findTaskById(state.tasks, taskId);
      if (task == null) {
        continue;
      }
      if (task.status == TransferStatus.awaitingConflictResolution) {
        _promptConflict(task);
        continue;
      }
      if (task.status == TransferStatus.completed ||
          task.status == TransferStatus.skipped ||
          task.status == TransferStatus.failed ||
          task.status == TransferStatus.cancelled) {
        _trackedUploadTaskIds.remove(taskId);
      }
    }
  }

  Future<void> _promptConflict(TransferTaskEntity task) async {
    if (!mounted || _activeConflictTaskId != null) {
      return;
    }

    _activeConflictTaskId = task.id;
    try {
      final resolution = await showUploadConflictDialog(
        context,
        fileName: task.fileName,
      );
      if (!mounted || resolution == null) {
        return;
      }
      await context.read<TransferCubit>().resolveUploadConflict(
        taskId: task.id,
        resolution: resolution,
      );
    } finally {
      _activeConflictTaskId = null;
    }
  }

  PartnerConversationMessage _buildMessage({
    required TransferTaskEntity task,
    required TransferCubit transferCubit,
  }) {
    final isOutgoing = task.direction == TransferDirection.upload;
    return PartnerConversationMessage(
      title: task.fileName,
      outgoing: isOutgoing,
      senderDisplayName: isOutgoing ? '本机' : '服务器',
      avatar: PartnerAvatarSpec(
        fallbackIcon: isOutgoing
            ? Icons.smartphone_rounded
            : Icons.dns_outlined,
        fallbackInitial: isOutgoing ? '本' : '服',
      ),
      content: PartnerMessageContent.file(title: task.fileName),
      metaCaption:
          '${task.formattedTransferred} / ${task.formattedSize} · ${formatPartnerTimestamp(task.createdAt)}',
      status: PartnerConversationStatusBadge(
        label: _statusLabel(task.status),
        backgroundColor: isOutgoing
            ? Colors.white.withValues(alpha: 0.16)
            : _statusBackgroundColor(task.status),
        foregroundColor: isOutgoing
            ? Colors.white
            : _statusForegroundColor(task.status),
      ),
      detailLines: [
        isOutgoing ? '发送到 ${task.remotePath}' : '接收到 ${task.localPath}',
      ],
      errorMessage: task.errorMessage,
      progress: _progressForDisplay(task),
      actions: [
        if (task.status == TransferStatus.transferring)
          PartnerConversationAction(
            label: '暂停',
            icon: Icons.pause_rounded,
            onTap: () => transferCubit.pauseTask(task.id),
          ),
        if (task.status == TransferStatus.paused)
          PartnerConversationAction(
            label: '继续',
            icon: Icons.play_arrow_rounded,
            onTap: () => transferCubit.resumeTask(task.id),
          ),
        if (_canCancel(task.status))
          PartnerConversationAction(
            label: '取消',
            icon: Icons.close_rounded,
            destructive: true,
            onTap: () => transferCubit.cancelTask(task.id),
          ),
      ],
    );
  }

  double? _progressForDisplay(TransferTaskEntity task) {
    if (task.status == TransferStatus.transferring ||
        task.status == TransferStatus.pending) {
      return task.progress.clamp(0.0, 1.0);
    }
    return null;
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

  _ServerTransferTarget _resolveTarget({
    required CurrentSession currentSession,
  }) {
    final rootId = (currentSession.rootId?.trim().isNotEmpty ?? false)
        ? currentSession.rootId!
        : 'fs';
    final root = currentSession.getRootById(rootId);
    return _ServerTransferTarget(
      path: NasPath.root(rootId),
      directoryLabel: _buildDirectoryLabel(rootName: root?.name, path: '/'),
      writable: root?.writable ?? true,
    );
  }

  String _buildDirectoryLabel({String? rootName, required String path}) {
    final resolvedRootName = (rootName?.trim().isNotEmpty ?? false)
        ? rootName!.trim()
        : '默认目录';
    if (path == '/') {
      return '$resolvedRootName /';
    }
    return '$resolvedRootName $path';
  }

  String _serverTitle(String? rawName) {
    final trimmed = rawName?.trim() ?? '';
    return trimmed.isEmpty ? '服务器文件收发' : '$trimmed 文件收发';
  }
}

class _ServerTransferTarget {
  final NasPath path;
  final String directoryLabel;
  final bool writable;

  const _ServerTransferTarget({
    required this.path,
    required this.directoryLabel,
    required this.writable,
  });
}

bool _canCancel(TransferStatus status) {
  return status == TransferStatus.pending ||
      status == TransferStatus.transferring ||
      status == TransferStatus.paused ||
      status == TransferStatus.awaitingConflictResolution;
}

String _statusLabel(TransferStatus status) {
  return switch (status) {
    TransferStatus.pending => '等待中',
    TransferStatus.paused => '已暂停',
    TransferStatus.transferring => '传输中',
    TransferStatus.awaitingConflictResolution => '等待处理',
    TransferStatus.completed => '已完成',
    TransferStatus.skipped => '已跳过',
    TransferStatus.failed => '失败',
    TransferStatus.cancelled => '已取消',
  };
}

Color _statusBackgroundColor(TransferStatus status) {
  return switch (status) {
    TransferStatus.completed => const Color(0xFFE7F6EC),
    TransferStatus.transferring ||
    TransferStatus.pending => const Color(0xFFEAF2FF),
    TransferStatus.awaitingConflictResolution ||
    TransferStatus.paused => const Color(0xFFFFF2DD),
    TransferStatus.failed ||
    TransferStatus.cancelled => const Color(0xFFFFE9E9),
    TransferStatus.skipped => const Color(0xFFF1F0ED),
  };
}

Color _statusForegroundColor(TransferStatus status) {
  return switch (status) {
    TransferStatus.completed => const Color(0xFF2F7D4A),
    TransferStatus.transferring ||
    TransferStatus.pending => const Color(0xFF375B9E),
    TransferStatus.awaitingConflictResolution ||
    TransferStatus.paused => const Color(0xFF8A5A00),
    TransferStatus.failed ||
    TransferStatus.cancelled => const Color(0xFFB64848),
    TransferStatus.skipped => const Color(0xFF77736E),
  };
}
