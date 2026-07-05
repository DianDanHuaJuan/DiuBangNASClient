import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';



import '../../../../app/di/service_locator.dart';

import '../../../../core/device/local_media_picker.dart';

import '../../../../core/node/device_display_extensions.dart';
import '../../../../core/node/unified_node.dart';

import '../../../../core/widgets/user_avatar.dart';

import '../../data/local/relay_preview_cache.dart';

import '../../domain/entities/relay_transfer_entity.dart';

import '../../domain/relay_media_kind.dart';

import '../cubit/relay_cubit.dart';

import '../cubit/relay_state.dart';

import '../utils/relay_transfer_progress.dart';
import '../utils/relay_transfer_tap.dart';
import '../utils/relay_transfer_tap_handler.dart';
import '../widgets/partner_conversation_page.dart';

import '../widgets/partner_message_content.dart';

class DeviceChatPage extends StatefulWidget {
  final String peerClientId;



  const DeviceChatPage({super.key, required this.peerClientId});



  @override

  State<DeviceChatPage> createState() => _DeviceChatPageState();

}



class _DeviceChatPageState extends State<DeviceChatPage> {

  static const _localMediaPicker = LocalMediaPicker();

  RelayCubit? _relayCubit;
  String? _peerAvatarPath;

  @override

  void initState() {

    super.initState();

    _relayCubit = context.read<RelayCubit>();

    _relayCubit!.setActivePeer(widget.peerClientId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _relayCubit?.markPeerRead(widget.peerClientId);
    });
    unawaited(_loadPeerAvatar());

  }

  Future<void> _loadPeerAvatar() async {
    final peer = _relayCubit?.peerById(widget.peerClientId);
    final deviceId =
        peer?.identity.deviceId ??
        peer?.identity.clientId ??
        widget.peerClientId;
    try {
      final path = await serviceLocator.peerAvatarCache.ensureCached(
        deviceId: deviceId,
        remoteUpdatedAt: peer?.client?.avatarUpdatedAt,
      );
      if (!mounted) {
        return;
      }
      setState(() => _peerAvatarPath = path);
    } catch (_) {}
  }



  @override

  void dispose() {

    _relayCubit?.setActivePeer(null);

    super.dispose();

  }



  @override

  Widget build(BuildContext context) {

    final relayCubit = context.read<RelayCubit>();

    return BlocListener<RelayCubit, RelayState>(

      listenWhen: (previous, current) =>

          previous.message != current.message ||

          previous.errorMessage != current.errorMessage,

      listener: (context, state) {

        final message = state.errorMessage ?? state.message;

        if (message == null || message.isEmpty) {

          return;

        }

        ScaffoldMessenger.of(context)

          ..hideCurrentSnackBar()

          ..showSnackBar(SnackBar(content: Text(message)));

        relayCubit.clearFeedback();

      },

      child: BlocBuilder<RelayCubit, RelayState>(

        builder: (context, state) {

          final selfClientId = relayCubit.currentClientId;

          final selfDisplayName = relayCubit.localDisplayName;

          final peer =

              relayCubit.peerById(widget.peerClientId) ??

              UnifiedNode.peerPlaceholder(clientId: widget.peerClientId);

          final peerHistory = state.peerHistory(widget.peerClientId);
          final transfers = peerHistory.transfers;

          return PartnerConversationPage(
            title: peer.publicDisplayName,
            peerOnline: peer.presence.status == PresenceStatus.online,
            hintMessage: _buildHintMessage(
              peerOnline: peer.presence.status == PresenceStatus.online,
            ),

            isLoading: peerHistory.isLoadingInitial && transfers.isEmpty,
            isLoadingOlder: peerHistory.isLoadingMore,
            hasMoreOlder: peerHistory.hasMore,

            messages: transfers

                .map(

                  (transfer) => _buildMessage(

                    context: context,

                    transfer: transfer,

                    currentClientId: selfClientId,

                    selfDisplayName: selfDisplayName,

                    peer: peer,

                    previewCache: relayCubit.previewCache,

                    localAvatarPath: serviceLocator.userProfileStore.avatarPath,

                    peerAvatarPath: _peerAvatarPath,

                    isBusy: state.busyTransferIds.contains(transfer.transferId),

                    downloadProgress:

                        state.downloadProgressByTransferId[transfer.transferId],

                    relayCubit: relayCubit,

                  ),

                )

                .toList(growable: false),

            onRefresh: () async {},
            onLoadOlder: () =>
                relayCubit.loadOlderPeerMessages(widget.peerClientId),

            emptyTitle: '还没有与 ${peer.publicDisplayName} 的 Relay 记录',

            emptyDescription: '点击底部按钮选择文件，客户端会按服务端 Relay 契约创建传输、分片上传并等待对方手动下载。',

            sendButtonLabel:

                state.isSending && state.sendingPeerId == widget.peerClientId

                ? '发送中...'

                : '发送文件',

            sendMediaButtonLabel:

                state.isSending && state.sendingPeerId == widget.peerClientId

                ? '发送中...'

                : '相册/视频',

            onSend: state.isSending

                ? null

                : () => relayCubit.sendFilesToPeer(widget.peerClientId),

            onSendMedia: state.isSending

                ? null

                : () => _pickAndSendMedia(context, relayCubit),

          );

        },

      ),

    );

  }



  String _buildHintMessage({
    required bool peerOnline,
  }) {
    final onlineHint = peerOnline
        ? '设备当前在线，发送后的 Relay 进度会通过 realtime 实时刷新。'
        : '设备当前离线，仍可发送离线中继文件；对方下次连线后会收到文件卡片。';

    return '$onlineHint\n下载完成后 NAS 释放文件，本地缩略图保留（100MB FIFO）。';
  }



  Future<void> _pickAndSendMedia(

    BuildContext context,

    RelayCubit relayCubit,

  ) async {

    final result = await _localMediaPicker.pickMedia(context);

    if (!context.mounted || result.items.isEmpty) {

      return;

    }

    final mimeByPath = <String, String>{

      for (final item in result.items)

        if (item.mimeType != null && item.mimeType!.trim().isNotEmpty)

          item.localPath: item.mimeType!.trim(),

    };

    await relayCubit.sendLocalPathsToPeer(

      widget.peerClientId,

      result.items.map((item) => item.localPath).toList(growable: false),

      mimeByPath: mimeByPath,

    );

  }



  PartnerConversationMessage _buildMessage({

    required BuildContext context,

    required RelayTransferEntity transfer,

    required String? currentClientId,

    required String selfDisplayName,

    required UnifiedNode peer,

    required RelayPreviewCache? previewCache,

    required String? localAvatarPath,

    String? peerAvatarPath,

    required bool isBusy,

    required double? downloadProgress,

    required RelayCubit relayCubit,

  }) {

    final selfClientId = currentClientId ?? '';

    final isOutgoing = transfer.isSender(selfClientId);

    final mediaKind = relayMediaKindFromTransfer(transfer);

    final thumbnailPath = previewCache?.thumbnailPathFor(transfer.transferId);

    final originalPath = previewCache?.originalPathFor(transfer.transferId);

    final originalIsContentUri =

        previewCache?.originalIsContentUri(transfer.transferId) ?? false;

    final canTap = relayTransferIsTappable(
      isOutgoing: isOutgoing,
      thumbnailPath: thumbnailPath,
      originalPath: originalPath,
    );

    final senderName = isOutgoing
        ? selfDisplayName
        : peer.publicDisplayName;

    final avatar = isOutgoing

        ? selfAvatarSpec(

            customAvatarPath: localAvatarPath,

            displayName: selfDisplayName,

          )

        : peerAvatarSpec(

            platform: peer.identity.platform,

            displayName: senderName,

            customAvatarPath: peerAvatarPath,

          );

    final content = _buildContent(

      transfer: transfer,

      mediaKind: mediaKind,

      thumbnailPath: thumbnailPath,

    );



    return PartnerConversationMessage(
      id: transfer.transferId,
      title: transfer.fileName,
      outgoing: isOutgoing,
      senderDisplayName: senderName,
      avatar: avatar,
      content: content,
      metaCaption:
          '${formatPartnerFileSize(transfer.fileSize)} · ${formatPartnerTimestamp(transfer.createdAt)}',
      status: const PartnerConversationStatusBadge(
        label: '',
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.transparent,
      ),
      onMediaTap: canTap
          ? () => handleRelayTransferTap(
              context: context,
              transfer: transfer,
              mediaKind: mediaKind,
              isOutgoing: isOutgoing,
              originalPath: originalPath,
              originalIsContentUri: originalIsContentUri,
              thumbnailPath: thumbnailPath,
              selfClientId: selfClientId,
              downloadTransfer: relayCubit.downloadTransferForPreview,
            )
          : null,
      progress: relayProgressForDisplay(
        transfer: transfer,
        isOutgoing: isOutgoing,
        downloadProgress: downloadProgress,
      ),
      progressLabel: relayProgressLabelForDisplay(
        transfer: transfer,
        isOutgoing: isOutgoing,
        downloadProgress: downloadProgress,
      ),
    );
  }



  PartnerMessageContent _buildContent({

    required RelayTransferEntity transfer,

    required RelayMediaKind mediaKind,

    required String? thumbnailPath,

  }) {

    if (mediaKind == RelayMediaKind.other) {

      return PartnerMessageContent.file(title: transfer.fileName);

    }

    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {

      return PartnerMessageContent.mediaPreview(

        mediaKind: mediaKind,

        thumbnailPath: thumbnailPath,

      );

    }

    return PartnerMessageContent.mediaPlaceholder(

      mediaKind: mediaKind,

      placeholderLabel: transfer.fileName,

    );

  }

}



String _statusLabel(RelayTransferEntity transfer, String? currentClientId) {

  final clientId = currentClientId ?? '';

  if (transfer.isSender(clientId)) {

    return switch (transfer.status) {

      RelayTransferStatus.created => '待上传',

      RelayTransferStatus.uploading => '上传中',

      RelayTransferStatus.ready => '待对方下载',

      RelayTransferStatus.downloading => '对方下载中',

      RelayTransferStatus.completed => '已送达',

      RelayTransferStatus.cancelled => '已取消',

      RelayTransferStatus.expired => '已过期',

      RelayTransferStatus.failed => '失败',

      RelayTransferStatus.interrupted => '已中断',

    };

  }

  return switch (transfer.status) {

    RelayTransferStatus.created => '待发送',

    RelayTransferStatus.uploading => '上传中',

    RelayTransferStatus.ready => '可下载',

    RelayTransferStatus.downloading => '下载中',

    RelayTransferStatus.completed => '已下载',

    RelayTransferStatus.failed => '失败',

    RelayTransferStatus.interrupted => '已中断',

    RelayTransferStatus.cancelled => '已取消',

    RelayTransferStatus.expired => '已过期',

  };

}



Color _statusBackgroundColor(RelayTransferStatus status) {

  return switch (status) {

    RelayTransferStatus.completed => const Color(0xFFE7F6EC),

    RelayTransferStatus.ready ||

    RelayTransferStatus.downloading => const Color(0xFFEAF2FF),

    RelayTransferStatus.failed ||

    RelayTransferStatus.cancelled ||

    RelayTransferStatus.expired ||

    RelayTransferStatus.interrupted => const Color(0xFFFFE9E9),

    RelayTransferStatus.created ||

    RelayTransferStatus.uploading => const Color(0xFFF1F0ED),

  };

}



Color _statusForegroundColor(RelayTransferStatus status) {

  return switch (status) {

    RelayTransferStatus.completed => const Color(0xFF2F7D4A),

    RelayTransferStatus.ready ||

    RelayTransferStatus.downloading => const Color(0xFF375B9E),

    RelayTransferStatus.failed ||

    RelayTransferStatus.cancelled ||

    RelayTransferStatus.expired ||

    RelayTransferStatus.interrupted => const Color(0xFFB64848),

    RelayTransferStatus.created ||

    RelayTransferStatus.uploading => const Color(0xFF6D6C6A),

  };

}


