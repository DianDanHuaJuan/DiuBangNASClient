import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/user_avatar.dart';
import '../../domain/relay_media_kind.dart';
import 'partner_message_content.dart';

class PartnerConversationPage extends StatefulWidget {
  final String title;
  final String? hintMessage;
  final bool? peerOnline;
  final bool isLoading;
  final bool isLoadingOlder;
  final bool hasMoreOlder;
  final List<PartnerConversationMessage> messages;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onLoadOlder;
  final String emptyTitle;
  final String emptyDescription;
  final String sendButtonLabel;
  final VoidCallback? onSend;
  final String? sendMediaButtonLabel;
  final VoidCallback? onSendMedia;

  const PartnerConversationPage({
    super.key,
    required this.title,
    this.hintMessage,
    this.peerOnline,
    required this.isLoading,
    this.isLoadingOlder = false,
    this.hasMoreOlder = false,
    required this.messages,
    required this.onRefresh,
    this.onLoadOlder,
    required this.emptyTitle,
    required this.emptyDescription,
    required this.sendButtonLabel,
    this.onSend,
    this.sendMediaButtonLabel,
    this.onSendMedia,
  });

  @override
  State<PartnerConversationPage> createState() =>
      _PartnerConversationPageState();
}

class _PartnerConversationPageState extends State<PartnerConversationPage> {
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;
  String? _lastFirstMessageId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (!widget.isLoading && widget.messages.isNotEmpty) {
      _lastMessageCount = widget.messages.length;
      _lastFirstMessageId = _messageId(widget.messages.first);
    }
  }

  @override
  void didUpdateWidget(covariant PartnerConversationPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isLoading && !widget.isLoading && widget.messages.isNotEmpty) {
      _lastMessageCount = widget.messages.length;
      _lastFirstMessageId = _messageId(widget.messages.first);
      return;
    }

    if (widget.messages.isEmpty) {
      _lastMessageCount = 0;
      _lastFirstMessageId = null;
      return;
    }

    final firstId = _messageId(widget.messages.first);
    final countChanged = widget.messages.length != _lastMessageCount;

    if (countChanged) {
      final prepended = _lastFirstMessageId != null &&
          firstId != _lastFirstMessageId &&
          widget.messages.length > _lastMessageCount;
      if (prepended) {
        _anchorScrollAfterPrepend();
      } else if (widget.messages.length > _lastMessageCount && _isNearBottom()) {
        _scheduleAnimateToBottom();
      }
      _lastMessageCount = widget.messages.length;
      _lastFirstMessageId = firstId;
    } else {
      _lastFirstMessageId ??= firstId;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  String _messageId(PartnerConversationMessage message) {
    return message.id ?? message.title;
  }

  PartnerConversationMessage _messageAtListIndex(int listIndex) {
    return widget.messages[widget.messages.length - 1 - listIndex];
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (widget.onLoadOlder == null) {
      return;
    }
    if (widget.isLoadingOlder || !widget.hasMoreOlder) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 48) {
      unawaited(widget.onLoadOlder!());
    }
  }

  void _scheduleAnimateToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _anchorScrollAfterPrepend() {
    if (!_scrollController.hasClients) {
      return;
    }
    final oldPixels = _scrollController.position.pixels;
    final oldMax = _scrollController.position.maxScrollExtent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      final newMax = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(oldPixels + (newMax - oldMax));
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    return _scrollController.position.pixels <= 80;
  }

  Future<void> _handleRefresh() async {
    if (widget.onLoadOlder != null) {
      await widget.onLoadOlder!();
      return;
    }
    await widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: Column(
        children: [
          if (widget.peerOnline != null)
            _OnlineIndicator(online: widget.peerOnline!)
          else if (widget.hintMessage != null)
            _PartnerHintBanner(message: widget.hintMessage!),
          if (widget.isLoadingOlder)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _handleRefresh,
                    child: widget.messages.isEmpty
                        ? _PartnerEmptyState(
                            title: widget.emptyTitle,
                            description: widget.emptyDescription,
                          )
                        : ListView.separated(
                            controller: _scrollController,
                            reverse: true,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                            itemCount: widget.messages.length,
                            itemBuilder: (context, index) {
                              return _PartnerChatMessageRow(
                                message: _messageAtListIndex(index),
                              );
                            },
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 16),
                          ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: _buildBottomActions(context),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    if (widget.onSendMedia != null && widget.sendMediaButtonLabel != null) {
      const accent = Color(0xFF3D8A5A);
      return Row(
        children: [
          const Spacer(flex: 1),
          Expanded(
            flex: 4,
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(21),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(21),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: widget.onSendMedia,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.photo_library_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.sendMediaButtonLabel!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(width: 1, color: Colors.white.withValues(alpha: 0.3)),
                    Expanded(
                      child: InkWell(
                        onTap: widget.onSend,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.attach_file_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.sendButtonLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(flex: 1),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: widget.onSend,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: const Icon(Icons.send_rounded),
      label: Text(widget.sendButtonLabel),
    );
  }
}

class PartnerConversationMessage {
  final String? id;
  final String title;
  final bool outgoing;
  final String senderDisplayName;
  final PartnerAvatarSpec avatar;
  final PartnerMessageContent content;
  final String? metaCaption;
  final PartnerConversationStatusBadge status;
  final List<String> detailLines;
  final String? errorMessage;
  final double? progress;
  final String? progressLabel;
  final List<PartnerConversationAction> actions;
  final VoidCallback? onMediaTap;

  const PartnerConversationMessage({
    this.id,
    required this.title,
    required this.outgoing,
    required this.senderDisplayName,
    required this.avatar,
    required this.content,
    this.metaCaption,
    required this.status,
    this.detailLines = const <String>[],
    this.errorMessage,
    this.progress,
    this.progressLabel,
    this.actions = const <PartnerConversationAction>[],
    this.onMediaTap,
  });
}

class PartnerConversationStatusBadge {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const PartnerConversationStatusBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });
}

class PartnerConversationAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool destructive;
  final bool iconOnly;

  const PartnerConversationAction({
    required this.label,
    required this.icon,
    this.onTap,
    this.destructive = false,
    this.iconOnly = false,
  });
}

class _PartnerChatMessageRow extends StatelessWidget {
  final PartnerConversationMessage message;

  const _PartnerChatMessageRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMedia =
        message.content.kind == PartnerMessageContentKind.mediaPreview ||
        message.content.kind == PartnerMessageContentKind.mediaPlaceholder;

    if (isMedia) {
      return _buildMediaRow(context);
    }

    return _buildBubbleRow(context);
  }

  Widget _buildMediaRow(BuildContext context) {
    final nameLabel = Padding(
      padding: EdgeInsets.only(
        left: message.outgoing ? 0 : 8,
        right: message.outgoing ? 8 : 0,
        bottom: 4,
      ),
      child: Text(
        message.senderDisplayName,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF9C9B99),
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final metaLine = message.metaCaption == null || message.metaCaption!.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.only(
              top: 4,
              left: message.outgoing ? 0 : 8,
              right: message.outgoing ? 8 : 0,
            ),
            child: Text(
              message.metaCaption!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFFB0AEAA),
              ),
            ),
          );

    return Align(
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Row(
          mainAxisAlignment: message.outgoing
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!message.outgoing) ...[
              UserAvatar(spec: message.avatar, size: 40),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: message.outgoing
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  nameLabel,
                  _buildBareMedia(context),
                  if (message.progress != null) ...[
                    const SizedBox(height: 6),
                    _MediaProgressBar(
                      progress: message.progress!,
                      label: message.progressLabel,
                    ),
                  ],
                  if (metaLine != null) metaLine,
                ],
              ),
            ),
            if (message.outgoing) ...[
              const SizedBox(width: 8),
              UserAvatar(spec: message.avatar, size: 40),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBareMedia(BuildContext context) {
    final child = switch (message.content.kind) {
      PartnerMessageContentKind.mediaPreview => _PartnerMediaPreview(
        mediaKind: message.content.mediaKind ?? RelayMediaKind.image,
        thumbnailPath: message.content.thumbnailPath!,
      ),
      _ => _PartnerMediaPlaceholder(
        mediaKind: message.content.mediaKind ?? RelayMediaKind.image,
        label: message.content.placeholderLabel ?? message.title,
      ),
    };

    if (message.onMediaTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: message.onMediaTap,
        child: child,
      ),
    );
  }

  Widget _buildBubbleRow(BuildContext context) {
    final bubble = _PartnerMessageBubble(message: message);
    final nameLabel = Padding(
      padding: EdgeInsets.only(
        left: message.outgoing ? 0 : 8,
        right: message.outgoing ? 8 : 0,
        bottom: 4,
      ),
      child: Text(
        message.senderDisplayName,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF9C9B99),
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final metaLine = message.metaCaption == null || message.metaCaption!.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.only(
              top: 4,
              left: message.outgoing ? 0 : 8,
              right: message.outgoing ? 8 : 0,
            ),
            child: Text(
              message.metaCaption!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFFB0AEAA),
              ),
            ),
          );

    final contentColumn = Column(
      crossAxisAlignment: message.outgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        nameLabel,
        bubble,
        if (message.progress != null) ...[
          const SizedBox(height: 6),
          _MediaProgressBar(
            progress: message.progress!,
            label: message.progressLabel,
          ),
        ],
        if (metaLine != null) metaLine,
      ],
    );

    return Align(
      alignment: message.outgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Row(
          mainAxisAlignment: message.outgoing
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!message.outgoing) ...[
              UserAvatar(spec: message.avatar, size: 40),
              const SizedBox(width: 8),
            ],
            Flexible(child: contentColumn),
            if (message.outgoing) ...[
              const SizedBox(width: 8),
              UserAvatar(spec: message.avatar, size: 40),
            ],
          ],
        ),
      ),
    );
  }
}

class _PartnerMessageBubble extends StatelessWidget {
  final PartnerConversationMessage message;

  const _PartnerMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    const primaryTextColor = Color(0xFF1A1918);
    const secondaryTextColor = Color(0xFF6D6C6A);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildContent(
            context,
            primaryTextColor,
            secondaryTextColor,
            onMediaTap: message.onMediaTap,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Color primaryTextColor,
    Color secondaryTextColor, {
    VoidCallback? onMediaTap,
  }) {
    final fileRow = Row(
      children: [
        Icon(
          Icons.insert_drive_file_outlined,
          color: primaryTextColor.withValues(alpha: 0.9),
          size: 22,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.content.title ?? message.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: primaryTextColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!message.outgoing && onMediaTap != null)
                Text(
                  '点击下载',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: secondaryTextColor,
                  ),
                ),
            ],
          ),
        ),
        if (!message.outgoing && onMediaTap != null) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.download_outlined,
            color: secondaryTextColor,
            size: 20,
          ),
        ],
      ],
    );

    if (onMediaTap == null) {
      return fileRow;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onMediaTap,
        child: fileRow,
      ),
    );
  }
}

class _PartnerMediaPreview extends StatelessWidget {
  final RelayMediaKind mediaKind;
  final String thumbnailPath;

  const _PartnerMediaPreview({
    required this.mediaKind,
    required this.thumbnailPath,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160, maxHeight: 160),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExtendedImage.file(
              File(thumbnailPath),
              fit: BoxFit.cover,
              width: 160,
              height: 160,
              loadStateChanged: (state) {
                if (state.extendedImageLoadState == LoadState.failed) {
                  return _PartnerMediaPlaceholder(
                    mediaKind: mediaKind,
                    label: null,
                  );
                }
                return null;
              },
            ),
            if (mediaKind == RelayMediaKind.video)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PartnerMediaPlaceholder extends StatelessWidget {
  final RelayMediaKind mediaKind;
  final String? label;

  const _PartnerMediaPlaceholder({
    required this.mediaKind,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    const iconColor = Color(0xFF6D6C6A);

    return Container(
      width: 160,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            mediaKind == RelayMediaKind.video
                ? Icons.videocam_outlined
                : Icons.image_outlined,
            size: 36,
            color: iconColor,
          ),
          if (label != null && label!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: iconColor.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PartnerHintBanner extends StatelessWidget {
  final String message;

  const _PartnerHintBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF5A6474),
          height: 1.4,
        ),
      ),
    );
  }
}

class _OnlineIndicator extends StatelessWidget {
  final bool online;

  const _OnlineIndicator({required this.online});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? const Color(0xFF4CAF50) : const Color(0xFFBDBDBD),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            online ? '在线' : '离线',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF9C9B99),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerEmptyState extends StatelessWidget {
  final String title;
  final String description;

  const _PartnerEmptyState({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.swap_horizontal_circle_outlined,
                size: 42,
                color: Color(0xFF9C9B99),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6D6C6A),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String formatPartnerFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class _MediaProgressBar extends StatelessWidget {
  final double progress;
  final String? label;

  const _MediaProgressBar({required this.progress, this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: const Color(0xFFE9E7E2),
            valueColor: const AlwaysStoppedAnimation<Color>(
              Color(0xFF3D8A5A),
            ),
          ),
        ),
        if (label != null && label!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            label!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF6D6C6A),
            ),
          ),
        ],
      ],
    );
  }
}

String formatPartnerTimestamp(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
