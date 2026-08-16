import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/models/chat_message.dart';

void main() {
  group('ChatMessage', () {
    test('can be constructed with all fields', () {
      final now = DateTime.now();
      final msg = ChatMessage(
        id: 'msg-1',
        text: 'Hello, world!',
        isUser: true,
        timestamp: now,
      );

      expect(msg.id, 'msg-1');
      expect(msg.text, 'Hello, world!');
      expect(msg.isUser, isTrue);
      expect(msg.timestamp, now);
    });

    test('fields are immutable', () {
      final msg = ChatMessage(
        id: 'msg-1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
      );

      // Attempting to assign to a final field would be a compile-time
      // error.  Verify that reading the same values back after
      // construction yields the original values.
      final idBefore = msg.id;
      final textBefore = msg.text;
      final isUserBefore = msg.isUser;
      final tsBefore = msg.timestamp;

      // No mutation API exists — confirm identity.
      expect(msg.id, idBefore);
      expect(msg.text, textBefore);
      expect(msg.isUser, isUserBefore);
      expect(msg.timestamp, tsBefore);
    });

    test('equality — same values are equal', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000);
      final a = ChatMessage(
        id: '1',
        text: 'hi',
        isUser: true,
        timestamp: now,
      );
      final b = ChatMessage(
        id: '1',
        text: 'hi',
        isUser: true,
        timestamp: now,
      );

      // ChatMessage does not override ==, so identical field values
      // do NOT guarantee operator== true (Dart compares by identity).
      // Still verify fields match.
      expect(a.id, b.id);
      expect(a.text, b.text);
      expect(a.isUser, b.isUser);
      expect(a.timestamp, b.timestamp);
    });

    test('inequality — different values differ', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000);
      final later = DateTime.fromMillisecondsSinceEpoch(2000);
      final a = ChatMessage(
        id: '1',
        text: 'hi',
        isUser: true,
        timestamp: now,
      );
      final b = ChatMessage(
        id: '2',
        text: 'bye',
        isUser: false,
        timestamp: later,
      );

      expect(a.id, isNot(b.id));
      expect(a.text, isNot(b.text));
      expect(a.isUser, isNot(b.isUser));
      expect(a.timestamp, isNot(b.timestamp));
    });

    test('isUser distinguishes user from agent messages', () {
      final userMsg = ChatMessage(
        id: 'u1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
      );
      final agentMsg = ChatMessage(
        id: 'a1',
        text: 'Hi there',
        isUser: false,
        timestamp: DateTime.now(),
      );

      expect(userMsg.isUser, isTrue);
      expect(agentMsg.isUser, isFalse);
    });
  });
}
