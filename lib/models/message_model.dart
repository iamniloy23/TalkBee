import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final String type;
  final String imageUrl;
  final Timestamp? timestamp;
  final bool delivered;
  final bool read;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.type,
    required this.imageUrl,
    required this.timestamp,
    required this.delivered,
    required this.read,
  });

  bool get isImage => type == 'image';

  factory MessageModel.fromDocument(
    DocumentSnapshot document,
  ) {
    final data =
        document.data()
            as Map<String, dynamic>;

    return MessageModel(
      id: document.id,
      senderId:
          data['senderId'] ?? '',
      receiverId:
          data['receiverId'] ?? '',
      text:
          data['text'] ?? '',
      type:
          data['type'] ?? 'text',
      imageUrl:
          data['imageUrl'] ?? '',
      timestamp:
          data['timestamp']
              as Timestamp?,
      delivered:
          data['delivered'] ?? false,
      read:
          data['read'] ?? false,
    );
  }
}