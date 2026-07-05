/// Represents the result of a single item in a batch delete operation
class BatchDeleteResultEntity {
  final String path;
  final bool success;
  final String? error;

  const BatchDeleteResultEntity({
    required this.path,
    required this.success,
    this.error,
  });

  factory BatchDeleteResultEntity.fromJson(Map<String, dynamic> json) {
    return BatchDeleteResultEntity(
      path: json['path'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'success': success,
        if (error != null) 'error': error,
      };
}
