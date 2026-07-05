/// 文件输入：原图本地路径、文件名、当前预览图来源
/// 文件职责：在当前预览图占位的基础上显示已下载完成的真正原图
/// 文件对外接口：OriginalImagePage
/// 文件包含：OriginalImagePage、_PreviewPlaceholder
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/preview_image_source.dart';
import '../widgets/image_preview_view.dart';

/// 输入：原图本地路径、文件名、当前预览图来源。
/// 职责：为用户展示已经下载完成的本地原图，并在原图解码完成前保持当前预览图作为占位。
/// 对外接口：OriginalImagePage widget。
class OriginalImagePage extends StatelessWidget {
  final String fileName;
  final String localPath;
  final PreviewImageSource? placeholderSource;

  const OriginalImagePage({
    super.key,
    required this.fileName,
    required this.localPath,
    this.placeholderSource,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(localPath);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (file.existsSync())
            SizedBox.expand(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (placeholderSource != null)
                    IgnorePointer(
                      child: ImagePreviewView(source: placeholderSource!),
                    ),
                  ExtendedImage.file(
                    file,
                    fit: BoxFit.contain,
                    mode: ExtendedImageMode.gesture,
                    clearMemoryCacheWhenDispose: false,
                    imageCacheName: 'original-image-view',
                    enableLoadState: true,
                    loadStateChanged: (state) {
                      switch (state.extendedImageLoadState) {
                        case LoadState.loading:
                          if (placeholderSource != null) {
                            return const SizedBox.expand();
                          }
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          );
                        case LoadState.completed:
                          return state.completedWidget;
                        case LoadState.failed:
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                '原图加载失败，请返回后重试。',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                      }
                    },
                    initGestureConfigHandler: (_) {
                      return GestureConfig(
                        minScale: 1.0,
                        animationMinScale: 0.8,
                        maxScale: 5.0,
                        animationMaxScale: 5.5,
                        speed: 1.0,
                        inertialSpeed: 100.0,
                        initialScale: 1.0,
                        cacheGesture: false,
                        inPageView: false,
                      );
                    },
                    layoutInsets: MediaQuery.of(context).padding,
                  ),
                ],
              ),
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '原图文件已不可用，请重新下载。',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Text(
              fileName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
