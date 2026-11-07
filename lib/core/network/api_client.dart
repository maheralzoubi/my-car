import 'package:dio/dio.dart';

import '../auth/session.dart';
import 'api_config.dart';

/// Dio wrapper shared by every API repository.
///
/// Auth: [session]'s token is read at request time (so a login/logout takes
/// effect on the very next request) and sent as `Authorization: Bearer …`,
/// but only to the API's own origin — absolute URLs to other hosts (CDNs,
/// photo links) never receive it.
///
/// 401s are NOT intercepted: the token is not cleared and there is no
/// refresh flow (the backend issues no refresh tokens). The 401 surfaces to
/// the caller like any other error (see `mapDioException`).
class ApiClient {
  /// [baseUrl] defaults to [ApiConfig.baseUrl]; [httpClientAdapter] swaps
  /// the transport (tests pass a fake so nothing leaves the process).
  ApiClient(
    this.session, {
    String? baseUrl,
    HttpClientAdapter? httpClientAdapter,
  }) : dio = Dio(
         BaseOptions(
           baseUrl: baseUrl ?? ApiConfig.baseUrl,
           connectTimeout: timeout,
           sendTimeout: timeout,
           receiveTimeout: timeout,
         ),
       ) {
    if (httpClientAdapter != null) dio.httpClientAdapter = httpClientAdapter;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = session.token;
          if (token != null && _isApiOrigin(options)) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  static const Duration timeout = Duration(seconds: 10);

  final Session session;
  final Dio dio;

  static bool _isApiOrigin(RequestOptions options) {
    final base = Uri.tryParse(options.baseUrl);
    if (base == null) return false;
    final target = options.uri;
    return target.scheme == base.scheme &&
        target.host == base.host &&
        target.port == base.port;
  }
}
