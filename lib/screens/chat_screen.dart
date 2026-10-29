import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/message_model.dart';

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ChatScreen extends StatefulWidget {
  final String name;
  final String userId;
  final bool online;
  final String photoUrl;

  const ChatScreen({
    super.key,
    required this.name,
    required this.userId,
    required this.online,
    required this.photoUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;
      
  final ImagePicker _imagePicker = ImagePicker();
      bool _uploadingImage = false;

  late final String _chatId;

  Timer? _typingTimer;

  bool _chatReady = false;
  bool _isSending = false;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();

    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return;
    }

    final ids = [
      currentUser.uid,
      widget.userId,
    ]..sort();

    _chatId = '${ids[0]}_${ids[1]}';

    _initializeChat();

    _messageController.addListener(_handleTyping);
  }

  Future<void> _initializeChat() async {
    try {
      final currentUser = _auth.currentUser;

      if (currentUser == null) {
        return;
      }

      final chatRef =
          _firestore.collection('chats').doc(_chatId);

      await chatRef.set({
        'participants': [
          currentUser.uid,
          widget.userId,
        ],
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _chatReady = true;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open chat: $e'),
        ),
      );
    }
  }

  void _handleTyping() {
    final text = _messageController.text.trim();

    if (text.isNotEmpty && !_isTyping) {
      _setTyping(true);
    }

    _typingTimer?.cancel();

    if (text.isNotEmpty) {
      _typingTimer = Timer(
        const Duration(seconds: 1),
        () {
          _setTyping(false);
        },
      );
    } else {
      _setTyping(false);
    }
  }

  Future<void> _setTyping(bool value) async {
    if (!_chatReady) return;

    if (_isTyping == value) return;

    _isTyping = value;

    final currentUser = _auth.currentUser;

    if (currentUser == null) return;

    try {
      await _firestore
          .collection('chats')
          .doc(_chatId)
          .set({
        'typing.${currentUser.uid}': value,
      }, SetOptions(merge: true));
    } catch (_) {
      // Don't interrupt typing if the indicator update fails.
    }
  }

  Future<void> _pickAndSendImage() async {
  final currentUser =
      _auth.currentUser;

  if (currentUser == null ||
      !_chatReady ||
      _uploadingImage) {
    return;
  }

  try {
    setState(() {
      _uploadingImage = true;
    });

    final pickedFile =
        await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (pickedFile == null) {
      return;
    }

    final Uint8List bytes =
        await pickedFile.readAsBytes();

    final messageRef = _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc();

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chat_media')
        .child(_chatId)
        .child('${messageRef.id}.jpg');

    await storageRef.putData(
      bytes,
      SettableMetadata(
        contentType: 'image/jpeg',
      ),
    );

    final imageUrl =
        await storageRef.getDownloadURL();

    await _firestore
        .collection('chats')
        .doc(_chatId)
        .set({
      'participants': [
        currentUser.uid,
        widget.userId,
      ],
      'lastMessage': '📷 Image',
      'lastMessageSenderId':
          currentUser.uid,
      'lastMessageTime':
          FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await messageRef.set({
      'senderId':
          currentUser.uid,
      'receiverId':
          widget.userId,
      'text': '',
      'type': 'image',
      'imageUrl': imageUrl,
      'timestamp':
          FieldValue.serverTimestamp(),
      'delivered': false,
      'read': false,
    });
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Unable to send image: $e',
        ),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _uploadingImage = false;
      });
    }
  }
}

  Future<void> sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || !_chatReady || _isSending) {
      return;
    }

    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    _messageController.clear();
    await _setTyping(false);

    try {
      final chatRef =
          _firestore.collection('chats').doc(_chatId);

      await chatRef.set({
        'participants': [
          currentUser.uid,
          widget.userId,
        ],
        'lastMessage': text,
        'lastMessageSenderId': currentUser.uid,
        'lastMessageTime':
            FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'senderId': currentUser.uid,
        'receiverId': widget.userId,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'delivered': false,
        'read': false,
      });

      await Future.delayed(
        const Duration(milliseconds: 100),
      );

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to send message: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _markMessagesAsRead(
    List<QueryDocumentSnapshot> docs,
  ) async {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return;
    }

    final unread = docs.where((doc) {
      final data =
          doc.data() as Map<String, dynamic>;

      return data['receiverId'] == currentUser.uid &&
          data['read'] == false;
    }).toList();

    if (unread.isEmpty) {
      return;
    }

    final batch = _firestore.batch();

    for (final document in unread) {
      batch.update(
        document.reference,
        {
          'delivered': true,
          'read': true,
        },
      );
    }

    try {
      await batch.commit();
    } catch (_) {
      // Don't break the UI if read-status update fails.
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }

    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) {
      return '';
    }

    final date = timestamp.toDate();

    final hour = date.hour == 0
        ? 12
        : date.hour > 12
            ? date.hour - 12
            : date.hour;

    final minute =
        date.minute.toString().padLeft(2, '0');

    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  @override
  void dispose() {
    _typingTimer?.cancel();

    _setTyping(false);

    _messageController.removeListener(_handleTyping);
    _messageController.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_chatReady) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.name),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final currentUserId = _auth.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,

        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.amber.shade200,
              child: Text(
                widget.name.isNotEmpty
                    ? widget.name[0].toUpperCase()
                    : '?',
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  StreamBuilder<DocumentSnapshot>(
                    stream: _firestore
                        .collection('users')
                        .doc(widget.userId)
                        .snapshots(),

                    builder: (context, snapshot) {
                      if (!snapshot.hasData ||
                          !snapshot.data!.exists) {
                        return const Text(
                          'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        );
                      }

                      final data =
                          snapshot.data!.data()
                              as Map<String, dynamic>;

                      final online =
                          data['online'] == true;

                      return Text(
                        online ? 'Online' : 'Offline',
                        style: TextStyle(
                          fontSize: 12,
                          color: online
                              ? Colors.green
                              : Colors.grey,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(
              Icons.videocam_outlined,
            ),
            onPressed: () {},
          ),
        ],
      ),

      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _firestore
                  .collection('chats')
                  .doc(_chatId)
                  .snapshots(),

              builder: (context, chatSnapshot) {
                final chatData =
                    chatSnapshot.data?.data()
                        as Map<String, dynamic>?;

                final typing =
                    chatData?['typing']
                        as Map<String, dynamic>?;

                final otherTyping =
                    typing?[widget.userId] == true;

                return Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<
                          QuerySnapshot>(
                        stream: _firestore
                            .collection('chats')
                            .doc(_chatId)
                            .collection('messages')
                            .orderBy(
                              'timestamp',
                              descending: false,
                            )
                            .snapshots(),

                        builder:
                            (context, snapshot) {
                          if (snapshot
                                  .connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child:
                                  CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Unable to load messages.\n\n'
                                '${snapshot.error}',
                                textAlign:
                                    TextAlign.center,
                              ),
                            );
                          }

                          final docs =
                              snapshot.data?.docs ??
                                  [];

                          _markMessagesAsRead(docs);

                          WidgetsBinding.instance
                              .addPostFrameCallback(
                            (_) => _scrollToBottom(),
                          );

                          if (docs.isEmpty) {
                            return const Center(
                              child: Text(
                                'No messages yet.\n'
                                'Send a message to start the conversation.',
                                textAlign:
                                    TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            controller:
                                _scrollController,
                            padding:
                                const EdgeInsets.all(
                              16,
                            ),
                            itemCount: docs.length,

                            itemBuilder:
                                (context, index) {
                              final message =
                                  MessageModel
                                      .fromDocument(
                                docs[index],
                              );

                              final isMe =
                                  message.senderId ==
                                      currentUserId;

                              return Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,

                                child: Container(
                                  constraints:
                                      BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(
                                              context,
                                            )
                                            .size
                                            .width *
                                        0.75,
                                  ),

                                  margin:
                                      const EdgeInsets.only(
                                    bottom: 10,
                                  ),

                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                    horizontal: 15,
                                    vertical: 10,
                                  ),

                                  decoration:
                                      BoxDecoration(
                                    color: isMe
                                        ? Colors
                                            .amber
                                            .shade400
                                        : Colors.white,
                                    borderRadius:
                                        BorderRadius
                                            .only(
                                      topLeft:
                                          const Radius
                                              .circular(
                                        18,
                                      ),
                                      topRight:
                                          const Radius
                                              .circular(
                                        18,
                                      ),
                                      bottomLeft:
                                          Radius.circular(
                                        isMe ? 18 : 4,
                                      ),
                                      bottomRight:
                                          Radius.circular(
                                        isMe ? 4 : 18,
                                      ),
                                    ),
                                  ),

                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .end,

                                    children: [
                                      Align(
                                        alignment:
                                            Alignment
                                                .centerLeft,
                                        child: Text(
                                          message.text,
                                          style:
                                              const TextStyle(
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 4,
                                      ),

                                      Row(
                                        mainAxisSize:
                                            MainAxisSize.min,
                                        children: [
                                          Text(
                                            _formatTime(
                                              message
                                                  .timestamp,
                                            ),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors
                                                  .grey
                                                  .shade700,
                                            ),
                                          ),

                                          if (isMe) ...[
                                            const SizedBox(
                                              width: 4,
                                            ),

                                            Icon(
                                              message.read
                                                  ? Icons
                                                      .done_all
                                                  : message
                                                          .delivered
                                                      ? Icons
                                                          .done_all
                                                      : Icons
                                                          .check,
                                              size: 14,
                                              color: message
                                                      .read
                                                  ? Colors
                                                      .blue
                                                  : Colors
                                                      .grey
                                                      .shade700,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),

                    AnimatedSwitcher(
                      duration: const Duration(
                        milliseconds: 200,
                      ),
                      child: otherTyping
                          ? const Padding(
                              key: ValueKey(
                                'typing',
                              ),
                              padding:
                                  EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                8,
                              ),
                              child: Align(
                                alignment:
                                    Alignment.centerLeft,
                                child: Text(
                                  'typing...',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle:
                                        FontStyle.italic,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey(
                                'not_typing',
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),

          SafeArea(
            child: Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.fromLTRB(
                10,
                8,
                10,
                8,
              ),

              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline,
                    ),
                    onPressed: () {},
                  ),

                  Expanded(
                    child: TextField(
                      controller:
                          _messageController,
                      textInputAction:
                          TextInputAction.send,
                      onSubmitted: (_) =>
                          sendMessage(),

                      decoration:
                          InputDecoration(
                        hintText:
                            'Type a message...',
                        filled: true,
                        fillColor:
                            Colors.grey.shade100,
                        border:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(
                            25,
                          ),
                          borderSide:
                              BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 5),
                  
                  CircleAvatar(
  radius: 20,
  backgroundColor: Colors.amber.shade200,
  backgroundImage: widget.photoUrl.isNotEmpty
      ? NetworkImage(widget.photoUrl)
      : null,
  child: widget.photoUrl.isEmpty
      ? Text(
          widget.name.isNotEmpty
              ? widget.name[0].toUpperCase()
              : '?',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        )
      : null,
),

                  CircleAvatar(
                    backgroundColor:
                        Colors.amber.shade400,
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.send,
                              color: Colors.black,
                              size: 20,
                            ),
                      onPressed:
                          _isSending
                              ? null
                              : sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}