/// 文件输入：设备列表、点击回调
/// 文件职责：使用搜索页服务器卡片样式显示设备列表
/// 文件对外接口：RelayDeviceSummary, RelayRecordList
/// 文件包含：RelayDeviceSummary, RelayRecordList
import 'package:flutter/material.dart';

import '../../../auth/presentation/widgets/server_entry_card.dart';

class RelayDeviceSummary {
  final String clientId;
  final String name;
  final String primaryText;
  final String secondaryText;
  final bool online;
  final bool isServer;
  final String tagLabel;
  final IconData leadingIcon;
  final bool isInteractive;
  final int unreadCount;

  const RelayDeviceSummary({
    required this.clientId,
    required this.name,
    required this.primaryText,
    required this.secondaryText,
    required this.online,
    this.isServer = false,
    required this.tagLabel,
    required this.leadingIcon,
    this.isInteractive = true,
    this.unreadCount = 0,
  });
}

class RelayRecordList extends StatelessWidget {
  final List<RelayDeviceSummary> devices;
  final ValueChanged<RelayDeviceSummary>? onTap;

  const RelayRecordList({super.key, required this.devices, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: devices.length,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (context, index) {
        final device = devices[index];
        return ServerEntryCard(
          title: device.name,
          primaryText: device.primaryText,
          secondaryText: device.secondaryText,
          statusLabel: device.tagLabel,
          leadingIcon: device.leadingIcon,
          isOnline: device.online,
          badgeCount: device.unreadCount > 0 ? device.unreadCount : null,
          onTap: onTap == null || !device.isInteractive
              ? null
              : () => onTap!.call(device),
        );
      },
      separatorBuilder: (context, index) => const SizedBox(height: 12),
    );
  }
}
