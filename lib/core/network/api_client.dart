import 'package:dio/dio.dart';

import '../auth/session.dart';
import 'api_config.dart';

class ApiClient {
  ApiClient(this.session)
      : dio = Dio(
          BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = session.token;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Session session;
  final Dio dio;
}
