import 'dart:io';

import 'package:image/image.dart';

bool isBackgroundGreen(int r, int g, int b) {
  const targetR = 0x3D;
  const targetG = 0x8A;
  const targetB = 0x5A;
  const tolerance = 55;

  final dr = (r - targetR).abs();
  final dg = (g - targetG).abs();
  final db = (b - targetB).abs();
  if (dr <= tolerance && dg <= tolerance && db <= tolerance) {
    return true;
  }

  return g > r + 25 && g > b + 25 && g >= 70;
}

Image removeGreenBackground(Image source) {
  final output = Image(width: source.width, height: source.height, numChannels: 4);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      if (isBackgroundGreen(r, g, b)) {
        output.setPixelRgba(x, y, 0, 0, 0, 0);
      } else {
        output.setPixelRgba(x, y, r, g, b, 255);
      }
    }
  }
  return output;
}

File resolveSourceFile() {
  const candidates = [
    'dsBuffer.bmp.png',
    'assets/source/dsBuffer.bmp.png',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  throw StateError('Missing source image. Expected dsBuffer.bmp.png or assets/source/dsBuffer.bmp.png.');
}

const _splashTargets = <String, int>{
  'android/app/src/main/res/drawable/splash_icon.png': 512,
  'android/app/src/main/res/drawable-mdpi/splash_icon.png': 128,
  'android/app/src/main/res/drawable-hdpi/splash_icon.png': 192,
  'android/app/src/main/res/drawable-xhdpi/splash_icon.png': 256,
  'android/app/src/main/res/drawable-xxhdpi/splash_icon.png': 384,
  'android/app/src/main/res/drawable-xxxhdpi/splash_icon.png': 512,
};

Future<void> main() async {
  final sourceFile = resolveSourceFile();
  final source = decodeImage(sourceFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('Failed to decode ${sourceFile.path}');
    exit(1);
  }

  final icon = copyResize(source, width: 1024, height: 1024);
  final foreground = copyResize(removeGreenBackground(source), width: 1024, height: 1024);
  final splashBase = icon;

  final assetsDir = Directory('assets')..createSync(recursive: true);
  final sourceDir = Directory('assets/source')..createSync(recursive: true);

  File('${assetsDir.path}/icon.png').writeAsBytesSync(encodePng(icon));
  File('${assetsDir.path}/icon_foreground.png').writeAsBytesSync(encodePng(foreground));

  for (final entry in _splashTargets.entries) {
    final target = File(entry.key);
    target.parent.createSync(recursive: true);
    final splash = copyResize(splashBase, width: entry.value, height: entry.value);
    target.writeAsBytesSync(encodePng(splash));
    stdout.writeln('Generated ${entry.key} (${entry.value}x${entry.value})');
  }

  if (sourceFile.path == 'dsBuffer.bmp.png') {
    final archivedSource = File('${sourceDir.path}/dsBuffer.bmp.png');
    if (archivedSource.existsSync()) {
      archivedSource.deleteSync();
    }
    sourceFile.renameSync(archivedSource.path);
    stdout.writeln('Archived source to assets/source/dsBuffer.bmp.png');
  }

  stdout.writeln('Generated assets/icon.png (${icon.width}x${icon.height})');
  stdout.writeln('Generated assets/icon_foreground.png (${foreground.width}x${foreground.height})');
}
