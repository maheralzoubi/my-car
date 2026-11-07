import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/network/api_exception.dart';

void main() {
  final req = RequestOptions(path: '/x', baseUrl: 'https://api.mycar.invalid');

  Response<dynamic> response(int status, [Object? data]) =>
      Response<dynamic>(requestOptions: req, statusCode: status, data: data);

  DioException bad(int status, [Object? data]) =>
      DioException.badResponse(statusCode: status, requestOptions: req, response: response(status, data));

  /// Dio's own developer-facing message must never reach the user.
  final notDioJargon = isNot(anyOf(
    contains('RequestOptions'),
    contains('validateStatus'),
    contains('developer.mozilla.org'),
    contains('DioException'),
  ));

  group('every DioExceptionType maps to a user-facing ApiException', () {
    const timeout = Duration(seconds: 10);
    final cases = <DioExceptionType, DioException>{
      DioExceptionType.connectionTimeout: DioException.connectionTimeout(timeout: timeout, requestOptions: req),
      DioExceptionType.sendTimeout: DioException.sendTimeout(timeout: timeout, requestOptions: req),
      DioExceptionType.receiveTimeout: DioException.receiveTimeout(timeout: timeout, requestOptions: req),
      DioExceptionType.badCertificate: DioException.badCertificate(requestOptions: req),
      DioExceptionType.badResponse: bad(500),
      DioExceptionType.cancel: DioException.requestCancelled(requestOptions: req, reason: 'user'),
      DioExceptionType.connectionError: DioException.connectionError(requestOptions: req, reason: 'Failed host lookup'),
      DioExceptionType.unknown: DioException(requestOptions: req, error: const FormatException('x')),
    };

    test('the table covers every enum value', () {
      // Fails when a dio upgrade adds a type, so it gets a deliberate mapping.
      final missing = DioExceptionType.values.toSet().difference(cases.keys.toSet());
      expect(missing.map((t) => t.name), anyOf(isEmpty, equals({'transformTimeout'})));
    });

    for (final entry in cases.entries) {
      test(entry.key.name, () {
        final mapped = mapDioException(entry.value);
        expect(mapped, isA<ApiException>());
        expect(mapped.message, isNotEmpty);
        expect(mapped.message, notDioJargon);
        expect(mapped.toString(), mapped.message);
      });
    }

    test('timeouts', () {
      for (final t in [DioExceptionType.connectionTimeout, DioExceptionType.sendTimeout, DioExceptionType.receiveTimeout]) {
        final mapped = mapDioException(cases[t]!);
        expect(mapped.message, 'Connection timed out. Please check your internet connection.');
        expect(mapped.statusCode, isNull);
      }
    });

    test('connectionError', () {
      final mapped = mapDioException(cases[DioExceptionType.connectionError]!);
      expect(mapped.message, 'Could not reach the server. Please check your internet connection.');
      expect(mapped.statusCode, isNull);
    });

    test('badCertificate', () {
      expect(mapDioException(cases[DioExceptionType.badCertificate]!).message,
          'Could not establish a secure connection to the server.');
    });

    test('cancel', () {
      expect(mapDioException(cases[DioExceptionType.cancel]!).message, 'The request was cancelled.');
    });

    test('unknown never echoes the underlying error', () {
      final e = DioException(requestOptions: req, error: Exception('internal'), message: 'internal detail');
      final mapped = mapDioException(e);
      expect(mapped.message, 'Something went wrong. Please try again.');
      expect(mapped.statusCode, isNull);
    });

    test('transformTimeout (and any future type) falls back to the generic message', () {
      final transform = DioExceptionType.values.where((t) => t.name == 'transformTimeout');
      for (final t in transform) {
        final mapped = mapDioException(DioException(requestOptions: req, type: t, message: 'dev text'));
        expect(mapped.message, 'Something went wrong. Please try again.');
      }
    });
  });

  group('badResponse', () {
    test('backend string message wins and keeps the status', () {
      final mapped = mapDioException(bad(400, {'statusCode': 400, 'message': 'address must be a string'}));
      expect(mapped.message, 'address must be a string');
      expect(mapped.statusCode, 400);
    });

    test('backend validation list is joined', () {
      final mapped = mapDioException(bad(400, {
        'message': ['email must be an email', 'password is too short'],
      }));
      expect(mapped.message, 'email must be an email, password is too short');
    });

    test('empty backend message falls back to the status message', () {
      expect(mapDioException(bad(400, {'message': ''})).message, 'Something went wrong. Please try again.');
      expect(mapDioException(bad(400, {'message': <String>[]})).message, 'Something went wrong. Please try again.');
    });

    test('non-map bodies are ignored', () {
      expect(mapDioException(bad(502, '<html>Bad gateway</html>')).message,
          'The server is having trouble right now. Please try again shortly.');
      expect(mapDioException(bad(500, ['message'])).statusCode, 500);
    });

    test('status-specific fallbacks', () {
      expect(mapDioException(bad(401)).message, 'Authentication failed. Please log in again.');
      expect(mapDioException(bad(403)).message, 'You do not have permission to do that.');
      expect(mapDioException(bad(404)).message, 'The requested item was not found.');
      expect(mapDioException(bad(500)).message, 'The server is having trouble right now. Please try again shortly.');
      expect(mapDioException(bad(503)).message, 'The server is having trouble right now. Please try again shortly.');
      expect(mapDioException(bad(422)).message, 'Something went wrong. Please try again.');
      for (final s in [401, 403, 404, 422, 500, 503]) {
        expect(mapDioException(bad(s)).statusCode, s);
        expect(mapDioException(bad(s)).message, notDioJargon);
      }
    });

    test('a backend message on a non-badResponse type still wins', () {
      final e = DioException(
        requestOptions: req,
        type: DioExceptionType.unknown,
        response: response(418, {'message': 'teapot'}),
      );
      final mapped = mapDioException(e);
      expect(mapped.message, 'teapot');
      expect(mapped.statusCode, 418);
    });
  });
}
