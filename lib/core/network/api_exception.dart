import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

ApiException mapDioException(DioException e) {
  final data = e.response?.data;
  if (data is Map && data['message'] != null) {
    final raw = data['message'];
    final message = raw is List ? raw.join(', ') : raw.toString();
    return ApiException(message, statusCode: e.response?.statusCode);
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return ApiException('Connection timed out. Please check your internet connection.');
    case DioExceptionType.connectionError:
      return ApiException('Could not reach the server. Please check your internet connection.');
    default:
      return ApiException(e.message ?? 'Something went wrong', statusCode: e.response?.statusCode);
  }
}
