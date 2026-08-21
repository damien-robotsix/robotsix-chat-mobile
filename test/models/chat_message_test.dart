import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/models/chat_message.dart';

void main() {
  // Non-const DateTime — prevents const construction of the whole message
  // so we test the general (runtime) path.
  final timestamp = DateTime.utc(2025, 1, 1, 12, 0, 0);

  group('ChatMessage', () {
    test('constructs with all four fields', () {
      final message = ChatMessage(
        id: 'msg-1',
        text: 'Hello, world!',
        isUser: true,
        timestamp: timestamp,
      );

      expect(message.id, equals('msg-1'));
      expect(message.text, equals('Hello, world!'));
      expect(message.isUser, isTrue);
      expect(message.timestamp, equals(timestamp));
    });

    test('immutability — copy produces a distinct instance with equal fields', () {
      final original = ChatMessage(
        id: 'original',
        text: 'immutable text',
        isUser: false,
        timestamp: timestamp,
      );

      final copy = ChatMessage(
        id: original.id,
        text: original.text,
        isUser: original.isUser,
        timestamp: original.timestamp,
      );

      // The copy is a different object (not identical), proving that the
      // class does not share mutable state via a singleton or cache.
      expect(identical(original, copy), isFalse);

      // Field values are faithfully preserved.
      expect(copy.id, equals(original.id));
      expect(copy.text, equals(original.text));
      expect(copy.isUser, equals(original.isUser));
      expect(copy.timestamp, equals(original.timestamp));
    });

    test('equality — same field values are structurally equivalent', () {
      final a = ChatMessage(
        id: 'eq',
        text: 'same',
        isUser: true,
        timestamp: timestamp,
      );
      final b = ChatMessage(
        id: 'eq',
        text: 'same',
        isUser: true,
        timestamp: timestamp,
      );

      expect(a.id, equals(b.id));
      expect(a.text, equals(b.text));
      expect(a.isUser, equals(b.isUser));
      expect(a.timestamp, equals(b.timestamp));
    });

    test('inequality — differing fields are distinguishable', () {
      final a = ChatMessage(
        id: '1',
        text: 'message A',
        isUser: true,
        timestamp: timestamp,
      );
      final b = ChatMessage(
        id: '2',
        text: 'message B',
        isUser: false,
        timestamp: timestamp.add(const Duration(seconds: 1)),
      );

      expect(a.id, isNot(equals(b.id)));
      expect(a.text, isNot(equals(b.text)));
      expect(a.isUser, isNot(equals(b.isUser)));
      expect(a.timestamp, isNot(equals(b.timestamp)));
      expect(identical(a, b), isFalse);
    });
  });
}