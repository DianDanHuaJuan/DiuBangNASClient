/// 文件输入：rootId、以 / 开头的业务路径
/// 文件职责：统一表达跨模块 NAS 业务路径，确保路径格式一致，提供 WebDAV 路径映射
/// 文件对外接口：NasPath
/// 文件包含：NasPath
class NasPath {
  final String rootId;
  final String path;

  const NasPath({required this.rootId, required this.path});

  factory NasPath.root(String rootId) {
    return NasPath(rootId: rootId, path: '/');
  }

  String get fullPath => path;

  List<String> get segments {
    if (path == '/') return [];
    return path.split('/').where((s) => s.isNotEmpty).toList();
  }

  String get fileName {
    if (path == '/') return '';
    final parts = path.split('/');
    return parts.last;
  }

  String get parentPath {
    if (path == '/') return '/';
    final parts = path.split('/');
    parts.removeLast();
    if (parts.isEmpty) return '/';
    return '/${parts.join('/')}';
  }

  NasPath append(String name) {
    final newPath = path == '/' ? '/$name' : '$path/$name';
    return NasPath(rootId: rootId, path: newPath);
  }

  NasPath parent() {
    return NasPath(rootId: rootId, path: parentPath);
  }

  bool get isRoot => path == '/';

  String toWebDavPath(String webdavBaseUrl, String rootPathPrefix) {
    final relativePath = path == '/' ? '' : path;
    return '$webdavBaseUrl$rootPathPrefix$relativePath';
  }

  static String buildApiPath(
    String rootId,
    String rootPath,
    String relativePath,
  ) {
    if (rootId == 'fs') {
      return '/fs$relativePath';
    } else if (rootId == 'library') {
      return '/library$relativePath';
    }
    return '/fs$relativePath';
  }

  String toApiPath() {
    final relativePath = path == '/' ? '' : path;
    return buildApiPath(rootId, '', relativePath);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NasPath && other.rootId == rootId && other.path == path;
  }

  @override
  int get hashCode => rootId.hashCode ^ path.hashCode;

  @override
  String toString() => 'NasPath(rootId: $rootId, path: $path)';
}
