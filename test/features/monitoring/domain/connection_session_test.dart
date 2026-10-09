import 'package:fav/features/monitoring/domain/connection_session.dart';
import 'package:fav/features/monitoring/domain/peer_event.dart';
import 'package:flutter_test/flutter_test.dart';

PeerEvent _ev(
  String peer,
  PeerEventType type,
  int sec, {
  int rx = 0,
  int tx = 0,
}) {
  return PeerEvent(
    serverId: 'srv',
    peerPublicKey: peer,
    type: type,
    serverTimestamp: DateTime.utc(2026, 5, 25, 12, 0, sec),
    rx: rx,
    tx: tx,
    latestHandshake: 0,
  );
}

void main() {
  test('a connect+disconnect pair produces one closed session', () {
    final sessions = ConnectionSession.derive([
      _ev('p1', PeerEventType.connect, 0),
      _ev('p1', PeerEventType.disconnect, 60, rx: 1024, tx: 2048),
    ]);
    expect(sessions, hasLength(1));
    expect(sessions.single.isOpen, isFalse);
    expect(sessions.single.rxBytes, 1024);
    expect(sessions.single.txBytes, 2048);
  });

  test('a lone connect produces an open session', () {
    final sessions = ConnectionSession.derive([
      _ev('p1', PeerEventType.connect, 0),
    ]);
    expect(sessions.single.isOpen, isTrue);
    expect(sessions.single.end, isNull);
  });

  test('a lone disconnect is ignored — open side trimmed by retention', () {
    final sessions = ConnectionSession.derive([
      _ev('p1', PeerEventType.disconnect, 60),
    ]);
    expect(sessions, isEmpty);
  });

  test('a second connect without a disconnect closes the previous session', () {
    final sessions = ConnectionSession.derive([
      _ev('p1', PeerEventType.connect, 0),
      _ev('p1', PeerEventType.connect, 120),
    ]);
    expect(sessions, hasLength(2));
    expect(sessions.first.end, isNotNull);
    expect(sessions.last.isOpen, isTrue);
  });

  test('multiple peers are isolated', () {
    final sessions = ConnectionSession.derive([
      _ev('p1', PeerEventType.connect, 0),
      _ev('p2', PeerEventType.connect, 10),
      _ev('p1', PeerEventType.disconnect, 60),
      _ev('p2', PeerEventType.disconnect, 90),
    ]);
    expect(sessions, hasLength(2));
    final p1 = sessions.firstWhere((s) => s.peerPublicKey == 'p1');
    final p2 = sessions.firstWhere((s) => s.peerPublicKey == 'p2');
    expect(p1.durationUntil(DateTime.utc(2027)).inSeconds, 60);
    expect(p2.durationUntil(DateTime.utc(2027)).inSeconds, 80);
  });

  test('byte counter resetting on the server is clamped to zero', () {
    // The agent restarted, so the disconnect carries a smaller rx than
    // the connect — a naive subtract would yield a negative number.
    final sessions = ConnectionSession.derive([
      _ev('p1', PeerEventType.connect, 0, rx: 1000, tx: 1000),
      _ev('p1', PeerEventType.disconnect, 60, rx: 5, tx: 5),
    ]);
    expect(sessions.single.rxBytes, 0);
    expect(sessions.single.txBytes, 0);
  });

  test('sessions are returned ordered by start (across peers)', () {
    final sessions = ConnectionSession.derive([
      _ev('p2', PeerEventType.connect, 10),
      _ev('p1', PeerEventType.connect, 0),
      _ev('p1', PeerEventType.disconnect, 30),
      _ev('p2', PeerEventType.disconnect, 40),
    ]);
    expect(sessions.first.peerPublicKey, 'p1');
    expect(sessions.last.peerPublicKey, 'p2');
  });
}
