import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/files/presentation/widgets/file_browser_floating_actions_widget.dart';

void main() {
  group('FileBrowserFloatingActionsWidget', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    Future<void> pumpHarness(
      WidgetTester tester, {
      required VoidCallback onUploadMediaTap,
      required VoidCallback onUploadFilesTap,
      bool showUploadAction = true,
      bool isUploading = false,
    }) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(primaryColor: const Color(0xFF3D8A5A)),
          home: Scaffold(
            body: Stack(
              children: [
                FileBrowserFloatingActionsWidget(
                  onUploadMediaTap: onUploadMediaTap,
                  onUploadFilesTap: onUploadFilesTap,
                  bottomPadding: 24,
                  showUploadAction: showUploadAction,
                  isUploading: isUploading,
                  uploadFileName: isUploading ? 'demo.txt' : null,
                  uploadProgress: 0.5,
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('expands upload menu with media and file options', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        onUploadMediaTap: () {},
        onUploadFilesTap: () {},
      );

      expect(find.text('图片/视频'), findsNothing);
      expect(find.text('文件'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(find.text('图片/视频'), findsOneWidget);
      expect(find.text('文件'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
    });

    testWidgets('toggles menu closed when main FAB is tapped again', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        onUploadMediaTap: () {},
        onUploadFilesTap: () {},
      );

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(find.text('图片/视频'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('图片/视频'), findsNothing);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('invokes media and file callbacks from expanded menu', (
      tester,
    ) async {
      var mediaTapped = false;
      var fileTapped = false;

      await pumpHarness(
        tester,
        onUploadMediaTap: () => mediaTapped = true,
        onUploadFilesTap: () => fileTapped = true,
      );

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pumpAndSettle();
      expect(mediaTapped, isTrue);
      expect(fileTapped, isFalse);
      expect(find.text('图片/视频'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.attach_file_rounded));
      await tester.pumpAndSettle();
      expect(fileTapped, isTrue);
    });

    testWidgets('shows options to the left when FAB is on the right', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        onUploadMediaTap: () {},
        onUploadFilesTap: () {},
      );

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      final mainFabCenter = tester.getCenter(find.byIcon(Icons.close_rounded));
      final mediaCenter = tester.getCenter(find.text('图片/视频'));
      expect(mediaCenter.dx, lessThan(mainFabCenter.dx));
    });

    testWidgets('shows upload progress pill while uploading', (tester) async {
      await pumpHarness(
        tester,
        onUploadMediaTap: () {},
        onUploadFilesTap: () {},
        isUploading: true,
      );

      expect(find.text('正在上传 demo.txt'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    });
  });
}
