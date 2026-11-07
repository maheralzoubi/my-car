import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Maps any [DioException] to a user-presentable [ApiException].
///
/// A backend-provided `message` (NestJS error body, string or list) wins.
/// Otherwise the message is a fixed, user-facing sentence per failure type —
/// never Dio's own developer-oriented text, which can include URLs and
/// troubleshooting prose. [ApiException.statusCode] is set whenever a
/// response was received.
ApiException mapDioException(DioException e) {
  final statusCode = e.response?.statusCode;
  final backendMessage = _backendMessage(e.response?.data);
  if (backendMessage != null) {
    return ApiException(backendMessage, statusCode: statusCode);
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return ApiException(
        'Connection timed out. Please check your internet connection.',
      );
    case DioExceptionType.connectionError:
      return ApiException(
        'Could not reach the server. Please check your internet connection.',
      );
    case DioExceptionType.badCertificate:
      return ApiException(
        'Could not establish a secure connection to the server.',
      );
    case DioExceptionType.badResponse:
      return ApiException(_statusMessage(statusCode), statusCode: statusCode);
    case DioExceptionType.cancel:
      return ApiException('The request was cancelled.');
    default:
      return ApiException(
        'Something went wrong. Please try again.',
        statusCode: statusCode,
      );
  }
}

String? _backendMessage(Object? data) {
  if (data is! Map) return null;
  final raw = data['message'];
  if (raw == null) return null;
  final message = raw is List ? raw.join(', ') : raw.toString();
  return message.trim().isEmpty ? null : message;
}

String _statusMessage(int? statusCode) {
  if (statusCode == 401) return 'Authentication failed. Please log in again.';
  if (statusCode == 403) return 'You do not have permission to do that.';
  if (statusCode == 404) return 'The requested item was not found.';
  if (statusCode != null && statusCode >= 500) {
    return 'The server is having trouble right now. Please try again shortly.';
  }
  return 'Something went wrong. Please try again.';
}
