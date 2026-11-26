import 'package:flutter_test/flutter_test.dart';
import 'package:superlivraison/models.dart';

import 'models_test.dart' show orderJson;

void main() {
  Map<String, dynamic> messageJson(Map<String, dynamic> extra) => {
        'id': 7,
        'order_id': 1,
        'client_uuid': 'a1',
        'sender_id': 3,
        'type': 'text',
        'body': 'Bonjour',
        'has_media': false,
        'duration_seconds': null,
        'lat': null,
        'lng': null,
        'delivered_at': null,
        'read_at': null,
        'created_at': '2026-11-26T10:00:00.000000Z',
        ...extra,
      };

  test('la discussion s\'ouvre quand un livreur est affecté', () {
    expect(Order.fromJson(orderJson({})).hasChat, isFalse);

    final order = Order.fromJson(orderJson({'has_courier': true, 'unread_messages': 2}));
    expect(order.hasChat, isTrue);
    expect(order.unreadMessages, 2);
  });

  test('un message du serveur garde ses accusés de lecture', () {
    final message = ChatMessage.fromJson(messageJson({'delivered_at': '2026-11-26T10:00:05.000000Z', 'read_at': '2026-11-26T10:01:00.000000Z'}));
    expect(message.isPending, isFalse);
    expect(message.deliveredAt, isNotNull);
    expect(message.readAt, isNotNull);
  });

  test('le message en cours d\'envoi garde son fichier local une fois reçu par le serveur', () {
    final draft = ChatMessage(
      clientUuid: 'a1',
      senderId: 3,
      type: 'voice',
      localPath: '/tmp/vocal.m4a',
      durationSeconds: 4,
      createdAt: DateTime.now(),
      state: SendState.sending,
    );
    expect(draft.isPending, isTrue);

    draft.absorb(ChatMessage.fromJson(messageJson({'type': 'voice', 'body': null, 'has_media': true, 'duration_seconds': 4})));

    expect(draft.id, 7);
    expect(draft.hasMedia, isTrue);
    expect(draft.localPath, '/tmp/vocal.m4a');
    expect(draft.isPending, isFalse);
  });
}
