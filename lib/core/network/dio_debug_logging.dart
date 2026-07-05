// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const nasDebugRequestIdHeader = 'x-nas-debug-request-id';

void attachDioDebugLogging(Dio dio, {required String channel}) {
  if (!kDebugMode) {
    return;
  }
  final alreadyAttached = dio.interceptors.any(
    (interceptor) => interceptor is _DioDebugLoggingInterceptor,
  );
  if (alreadyAttached) {
    return;
  }
  dio.interceptors.add(_DioDebugLoggingInterceptor(channel: channel));
}

String? extractDioDebugRequestId(Response<dynamic>? response) {
  return response?.headers.value(nasDebugRequestIdHeader);
}

class _DioDebugLoggingInterceptor extends Interceptor {
  _DioDebugLoggingInterceptor({required this.channel});

  final String channel;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    final requestOptions = err.requestOptions;
    final debugRequestId = extractDioDebugRequestId(response) ?? '-';
    final message =
        '[dio][$channel] '
        'type=${err.type.name} '
        'method=${requestOptions.method} '
        'url=${requestOptions.uri} '
        'status=${response?.statusCode} '
        'requestId=$debugRequestId '
        'requestHeaders=${_summarizeHeaders(requestOptions.headers)} '
        'message=${err.message ?? '-'} '
        'responseBody=${_truncate(_stringifyPayload(response?.data))}';

    developer.log(
      message,
      name: 'nas_client.http',
      error: err.error ?? err,
      stackTrace: err.stackTrace,
    );
    print(message);

    handler.next(err);
  }

  String _summarizeHeaders(Map<String, dynamic> headers) {
    final summarized = <String, dynamic>{};

    void addIfPresent(String key, {bool redact = false}) {
      final value = headers[key];
      if (value == null) {
        return;
      }
      summarized[key] = redact ? '<redacted>' : '$value';
    }

    addIfPresent('Authorization', redact: true);
    addIfPresent('Content-Length');
    addIfPresent('Content-Type');
    addIfPresent('Range');
    addIfPresent('X-NAS-Conflict-Policy');
    addIfPresent('x-nas-conflict-policy');

    return jsonEncode(summarized);
  }

  String _stringifyPayload(dynamic payload) {
    if (payload == null) {
      return '<empty>';
    }
    if (payload is String) {
      return payload;
    }
    try {
      return jsonEncode(payload);
    } catch (_) {
      return '$payload';
    }
  }

  String _truncate(String value) {
    const maxLength = 1200;
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...<truncated>';
  }
}
