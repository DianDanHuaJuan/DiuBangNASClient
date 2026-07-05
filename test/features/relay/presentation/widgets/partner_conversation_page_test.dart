import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/relay/domain/relay_media_kind.dart';
import 'package:nasclient/features/relay/presentation/widgets/partner_conversation_page.dart';
import 'package:nasclient/features/relay/presentation/widgets/partner_message_content.dart';

void main() {
  group('PartnerConversationPage', () {
    testWidgets('renders chat row with sender name, avatar and media placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PartnerConversationPage(
            title: 'Phone 01',
            hintMessage: 'hint',
            isLoading: false,
            messages: _sampleMessages(),
            onRefresh: () async {},
            emptyTitle: 'empty',
            emptyDescription: 'desc',
            sendButtonLabel: '发送文件',
            sendMediaButtonLabel: '相册/视频',
            onSend: () {},
            onSendMedia: () {},
          ),
        ),
      );

      expect(find.text('Phone 01'), findsNWidgets(2));
      expect(find.text('本机'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('1.2 MB · 2026-06-06 12:00'), findsOneWidget);
      expect(find.text('相册/视频'), findsOneWidget);
      expect(find.text('发送文件'), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('anchors at latest message when opened with cached messages', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PartnerConversationPage(
            title: 'Phone 01',
            isLoading: false,
            messages: _sampleMessages(),
            onRefresh: () async {},
            emptyTitle: 'empty',
            emptyDescription: 'desc',
            sendButtonLabel: '发送文件',
            onSend: () {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView));
      final controller = listView.controller!;
      expect(controller.hasClients, isTrue);
      expect(controller.offset, closeTo(0, 1));
      expect(find.text('notes.txt'), findsOneWidget);
    });

    testWidgets('anchors at latest message after simulated re-entry', (
      tester,
    ) async {
      final page = PartnerConversationPage(
        title: 'Phone 01',
        isLoading: false,
        messages: _sampleMessages(),
        onRefresh: () async {},
        emptyTitle: 'empty',
        emptyDescription: 'desc',
        sendButtonLabel: '发送文件',
        onSend: () {},
      );

      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView));
      final controller = listView.controller!;
      expect(controller.hasClients, isTrue);
      expect(controller.offset, closeTo(0, 1));
    });

    testWidgets('anchors at latest after initial loading completes', (
      tester,
    ) async {
      final messages = _sampleMessages();

      await tester.pumpWidget(
        MaterialApp(
          home: PartnerConversationPage(
            title: 'Phone 01',
            isLoading: true,
            messages: const [],
            onRefresh: () async {},
            emptyTitle: 'empty',
            emptyDescription: 'desc',
            sendButtonLabel: '发送文件',
            onSend: () {},
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PartnerConversationPage(
            title: 'Phone 01',
            isLoading: false,
            messages: messages,
            onRefresh: () async {},
            emptyTitle: 'empty',
            emptyDescription: 'desc',
            sendButtonLabel: '发送文件',
            onSend: () {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView));
      final controller = listView.controller!;
      expect(controller.hasClients, isTrue);
      expect(controller.offset, closeTo(0, 1));
    });
  });

  group('relayMediaKindFromTransfer', () {
    test('detects image from mime type', () {
      expect(
        relayMediaKindFromMime('image/jpeg'),
        RelayMediaKind.image,
      );
      expect(
        relayMediaKindFromMime('video/mp4'),
        RelayMediaKind.video,
      );
      expect(
        relayMediaKindFromMime('application/pdf'),
        RelayMediaKind.other,
      );
    });
  });
}

List<PartnerConversationMessage> _sampleMessages() {
  return [
    PartnerConversationMessage(
      id: 'msg-old',
      title: 'photo.jpg',
      outgoing: false,
      senderDisplayName: 'Phone 01',
      avatar: const PartnerAvatarSpec(
        fallbackIcon: Icons.phone_iphone_rounded,
        fallbackInitial: 'P',
      ),
      content: const PartnerMessageContent.mediaPlaceholder(
        mediaKind: RelayMediaKind.image,
        placeholderLabel: 'photo.jpg',
      ),
      metaCaption: '1.2 MB · 2026-06-06 12:00',
      status: const PartnerConversationStatusBadge(
        label: '可下载',
        backgroundColor: Color(0xFFEAF2FF),
        foregroundColor: Color(0xFF375B9E),
      ),
    ),
    PartnerConversationMessage(
      id: 'msg-new',
      title: 'notes.txt',
      outgoing: true,
      senderDisplayName: '本机',
      avatar: const PartnerAvatarSpec(
        fallbackIcon: Icons.smartphone_rounded,
        fallbackInitial: '本',
      ),
      content: const PartnerMessageContent.file(title: 'notes.txt'),
      metaCaption: '512 B · 2026-06-06 12:05',
      status: const PartnerConversationStatusBadge(
        label: '已送达',
        backgroundColor: Color(0x33FFFFFF),
        foregroundColor: Colors.white,
      ),
    ),
  ];
}
