import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mycar/core/auth/session.dart';
import 'package:mycar/core/network/api_client.dart';
import 'package:mycar/core/network/socket_client.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';
import 'package:mycar/modules/roadside/data/repositories/roadside_repository.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// ─────────────────────────────────────────────────────────────────────────────
// JSON fixtures shaped like my-car-backend's `toRequestResponse` /
// `toPublicDriver` (src/service-requests/service-requests.mapper.ts).
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> driverJson({Map<String, dynamic> overrides = const {}}) => {
      'id': 'drv-1',
      'name': 'Ahmed Al-Rashidi',
      'phone': '+966501234567',
      'rating': 4.9,
      'totalJobs': 1243,
      'vehicleType': 'Flatbed Carrier',
      'vehiclePlate': 'ABC 1234',
      'avatarInitials': 'AA',
      ...overrides,
    };

Map<String, dynamic> requestJson({Map<String, dynamic> overrides = const {}}) => {
      'id': 'req-1',
      'customerId': 'cust-9',
      'customerName': 'Sara',
      'customerPhone': '+966500000000',
      'serviceType': 'batteryJump',
      'pickupLocation': {'lat': 24.7136, 'lng': 46.6753},
      'pickupAddress': 'Olaya St, Riyadh',
      'estimatedPrice': 77.5,
      'finalPrice': null,
      'estimatedMinutes': 15,
      'status': 'searching',
      'driverLocation': null,
      'notes': null,
      'photoUrls': <String>[],
      'rating': null,
      'review': null,
      'assignedDriver': null,
      'paymentMethod': 'cash',
      'cashCollected': false,
      'createdAt': '2026-10-01T10:00:00.000Z',
      ...overrides,
    };

// ─────────────────────────────────────────────────────────────────────────────
// Dio transport fake: swaps the HttpClientAdapter so no request ever leaves
// the process. Every request is recorded; unrouted requests fail loudly.
// ─────────────────────────────────────────────────────────────────────────────

class FakeReply {
  FakeReply(this.statusCode, [this.body]);
  final int statusCode;
  final Object? body;
}

class RecordedRequest {
  RecordedRequest(this.options, this.body);
  final RequestOptions options;

  /// JSON-decoded request body as it went over the wire (null if no body).
  /// Multipart bodies are kept as raw text; inspect [form] for their parts.
  final Object? body;

  /// The multipart form, for upload requests.
  FormData? get form => options.data is FormData ? options.data as FormData : null;

  String get method => options.method;
  Uri get uri => options.uri;
  Map<String, dynamic> get headers => options.headers;
}

typedef FakeRoute = FutureOr<FakeReply> Function(RequestOptions options);

class FakeHttpAdapter implements HttpClientAdapter {
  final Map<String, FakeRoute> routes = {};
  final List<RecordedRequest> requests = [];

  /// Register a handler for `"METHOD /path"`.
  void on(String method, String path, FakeRoute route) {
    routes['${method.toUpperCase()} $path'] = route;
  }

  void reply(String method, String path, int status, [Object? body]) {
    on(method, path, (_) => FakeReply(status, body));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body;
    if (requestStream != null) {
      final bytes = await requestStream.expand((chunk) => chunk).toList();
      if (options.data is FormData) {
        body = utf8.decode(bytes, allowMalformed: true);
      } else {
        final text = utf8.decode(bytes);
        body = text.isEmpty ? null : jsonDecode(text);
      }
    }
    requests.add(RecordedRequest(options, body));

    final key = '${options.method.toUpperCase()} ${options.uri.path}';
    final route = routes[key];
    if (route == null) {
      throw StateError('FakeHttpAdapter: no route for $key');
    }
    final reply = await route(options);
    return ResponseBody.fromString(
      reply.body == null ? '' : jsonEncode(reply.body),
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// In-memory secure storage so [Session.load] works without a platform channel.
class FakeSecureStorage implements FlutterSecureStorage {
  FakeSecureStorage([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key] as String?;
    switch (invocation.memberName) {
      case #read:
        return Future<String?>.value(values[key]);
      case #write:
        values[key!] = invocation.namedArguments[#value] as String;
        return Future<void>.value();
      case #deleteAll:
        values.clear();
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// Builds a real [ApiClient] (so its auth interceptor is exercised) whose
/// transport is [adapter]. Never touches the network.
Future<ApiClient> buildApiClient(FakeHttpAdapter adapter, {String? token}) async {
  final session = Session(FakeSecureStorage({if (token != null) 'auth_token': token}));
  await session.load();
  final client = ApiClient(session);
  client.dio.httpClientAdapter = adapter;
  return client;
}

// ─────────────────────────────────────────────────────────────────────────────
// Socket fakes.
// ─────────────────────────────────────────────────────────────────────────────

/// Stands in for a connected Socket.IO socket. Only `on`/`off` are used by the
/// roadside repository; [serverEmit] simulates the backend pushing an event.
class FakeSocket implements io.Socket {
  final Map<String, List<dynamic Function(dynamic)>> handlers = {};

  @override
  void on(String event, dynamic Function(dynamic) handler) {
    handlers.putIfAbsent(event, () => []).add(handler);
  }

  @override
  void off(String event, [dynamic Function(dynamic)? handler]) {
    if (handler == null) {
      handlers.remove(event);
    } else {
      handlers[event]?.remove(handler);
      if (handlers[event]?.isEmpty ?? false) handlers.remove(event);
    }
  }

  int handlerCount(String event) => handlers[event]?.length ?? 0;

  int get totalHandlers => handlers.values.fold(0, (sum, l) => sum + l.length);

  void serverEmit(String event, Object? data) {
    for (final h in List.of(handlers[event] ?? const [])) {
      h(data);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('FakeSocket: ${invocation.memberName} not faked');
}

class FakeSocketClient extends SocketClient {
  FakeSocketClient(this.fake) : super(Session(FakeSecureStorage()));
  final FakeSocket fake;

  @override
  io.Socket get socket => fake;

  @override
  io.Socket connect() => fake;

  @override
  void disconnect() {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Controllable repository for bloc tests.
// ─────────────────────────────────────────────────────────────────────────────

ServiceRequest sampleRequest({
  String id = 'req-1',
  RequestStatus status = RequestStatus.searching,
  ServiceType type = ServiceType.batteryJump,
}) {
  return ServiceRequest(
    id: id,
    serviceType: type,
    customerLocation: const LatLng(24.7136, 46.6753),
    customerAddress: 'Olaya St, Riyadh',
    estimatedPrice: 77.5,
    estimatedMinutes: 15,
    status: status,
    createdAt: DateTime.utc(2026, 10, 1, 10),
  );
}

class FakeRoadsideRepository implements RoadsideRepository {
  double price = 80.0;
  Object? priceError;
  Object? createError;
  Object? cancelError;
  Object? rateError;
  Object? uploadError;
  ServiceRequest? createResult;

  /// Each [uploadPhotos] call's paths. URLs are `/uploads/request-photos/<path basename>`
  /// unless [uploadResult] overrides them.
  final List<List<String>> uploadCalls = [];
  List<String> Function(List<String> paths)? uploadResult;

  /// `photoUrls` of each [createRequestWithPhotos] call.
  final List<List<String>> createPhotoUrls = [];

  final List<Map<String, Object?>> createCalls = [];
  final List<(ServiceType, LatLng)> priceCalls = [];
  final List<String> cancelCalls = [];
  final List<(String, int, String?)> rateCalls = [];
  final List<String> watchCalls = [];

  final Map<String, StreamController<ServiceRequest>> watchers = {};

  StreamController<ServiceRequest> watcher(String id) =>
      watchers.putIfAbsent(id, () => StreamController<ServiceRequest>.broadcast());

  @override
  Future<double> getEstimatedPrice(ServiceType type, LatLng location) async {
    priceCalls.add((type, location));
    if (priceError != null) throw priceError!;
    return price;
  }

  @override
  Future<String> reverseGeocode(LatLng location) async => 'Somewhere';

  @override
  Future<ServiceRequest> createRequest({
    required ServiceType type,
    required LatLng location,
    required String address,
    String? notes,
  }) async {
    createCalls.add({'type': type, 'location': location, 'address': address, 'notes': notes});
    if (createError != null) throw createError!;
    return createResult ?? sampleRequest(type: type);
  }

  @override
  Future<List<String>> uploadPhotos(List<String> paths) async {
    uploadCalls.add(List.of(paths));
    if (uploadError != null) throw uploadError!;
    return uploadResult?.call(paths) ??
        [for (final p in paths) '/uploads/request-photos/${p.split('/').last}'];
  }

  /// Records [photoUrls] in [createPhotoUrls], then goes through
  /// [createRequest] so subclasses that gate or fail it apply here too.
  @override
  Future<ServiceRequest> createRequestWithPhotos({
    required ServiceType type,
    required LatLng location,
    required String address,
    String? notes,
    required List<String> photoUrls,
  }) {
    createPhotoUrls.add(List.of(photoUrls));
    return createRequest(type: type, location: location, address: address, notes: notes);
  }

  @override
  Stream<ServiceRequest> watchRequest(String requestId) {
    watchCalls.add(requestId);
    return watcher(requestId).stream;
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    cancelCalls.add(requestId);
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<void> rateDriver(String requestId, int stars, String? review) async {
    rateCalls.add((requestId, stars, review));
    if (rateError != null) throw rateError!;
  }

  @override
  Future<List<ServiceRequest>> getHistory() async => const [];
}
