import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/auth/session.dart';

import 'helpers/network_fakes.dart';

void main() {
  late FakeSecureStorage storage;
  late Session session;

  Future<void> save(Session s, {String token = 'tok'}) => s.save(
        token: token,
        userId: 'u1',
        role: 'customer',
        name: 'Maher',
        email: 'm@example.com',
        phone: '+966500000000',
      );

  setUp(() {
    storage = FakeSecureStorage();
    session = Session(storage);
  });

  test('starts logged out with nothing loaded', () async {
    await session.load();
    expect(session.isLoggedIn, isFalse);
    expect(session.token, isNull);
    expect(session.userId, isNull);
  });

  test('save updates memory and persists every field to secure storage', () async {
    await save(session);
    expect(session.isLoggedIn, isTrue);
    expect(session.token, 'tok');
    expect(session.role, 'customer');
    expect(storage.values, {
      'auth_token': 'tok',
      'auth_user_id': 'u1',
      'auth_role': 'customer',
      'auth_name': 'Maher',
      'auth_email': 'm@example.com',
      'auth_phone': '+966500000000',
    });
  });

  test('survives an app restart (new Session over the same storage)', () async {
    await save(session);
    final restarted = Session(storage);
    expect(restarted.isLoggedIn, isFalse, reason: 'nothing in memory until load()');
    await restarted.load();
    expect(restarted.isLoggedIn, isTrue);
    expect(restarted.token, 'tok');
    expect(restarted.userId, 'u1');
    expect(restarted.name, 'Maher');
    expect(restarted.email, 'm@example.com');
    expect(restarted.phone, '+966500000000');
    expect(restarted.role, 'customer');
  });

  test('a second save overwrites the first', () async {
    await save(session, token: 'old');
    await save(session, token: 'new');
    expect(session.token, 'new');
    expect(storage.values['auth_token'], 'new');
  });

  test('clear wipes memory and storage, so a restart stays logged out', () async {
    await save(session);
    await session.clear();
    expect(session.isLoggedIn, isFalse);
    expect(session.token, isNull);
    expect(session.email, isNull);
    expect(storage.values, isEmpty);
    expect(storage.calls, contains('deleteAll'));

    final restarted = Session(storage);
    await restarted.load();
    expect(restarted.isLoggedIn, isFalse);
  });

  test('token is cleared in memory before storage finishes (no stale token window)', () async {
    await save(session);
    final pending = session.clear();
    expect(session.token, isNull);
    await pending;
  });
}
