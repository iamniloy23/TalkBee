import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  final TextEditingController _searchController =
      TextEditingController();

  String _searchText = '';

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      setState(() {
        _searchText =
            _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) {
      return '';
    }

    final date = timestamp.toDate();
    final now = DateTime.now();

    final sameDay =
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    if (sameDay) {
      final hour = date.hour == 0
          ? 12
          : date.hour > 12
              ? date.hour - 12
              : date.hour;

      final minute =
          date.minute.toString().padLeft(2, '0');

      final period =
          date.hour >= 12 ? 'PM' : 'AM';

      return '$hour:$minute $period';
    }

    final yesterday = DateTime(
      now.year,
      now.month,
      now.day - 1,
    );

    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please log in again.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chats',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: Column(
        children: [
          // Search conversations
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              12,
              16,
              10,
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('chats')
                  .where(
                    'participants',
                    arrayContains: currentUser.uid,
                  )
                  .snapshots(),

              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Unable to load chats.\n\n'
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs =
                    snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 80,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 20),
                        Text(
                          'No conversations yet.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Open Contacts and start a chat.',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Sort newest conversations first.
                final sortedDocs = [...docs];

                sortedDocs.sort((a, b) {
                  final aData =
                      a.data() as Map<String, dynamic>;

                  final bData =
                      b.data() as Map<String, dynamic>;

                  final aTime =
                      aData['lastMessageTime'];

                  final bTime =
                      bData['lastMessageTime'];

                  if (aTime is Timestamp &&
                      bTime is Timestamp) {
                    return bTime.compareTo(aTime);
                  }

                  if (aTime is Timestamp) {
                    return -1;
                  }

                  if (bTime is Timestamp) {
                    return 1;
                  }

                  return 0;
                });

                // Search filtering.
                final filteredDocs =
                    sortedDocs.where((doc) {
                  final data =
                      doc.data()
                          as Map<String, dynamic>;

                  final lastMessage =
                      (data['lastMessage'] ?? '')
                          .toString()
                          .toLowerCase();

                  if (_searchText.isEmpty) {
                    return true;
                  }

                  return lastMessage
                      .contains(_searchText);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No matching conversations.',
                      style: TextStyle(
                        fontSize: 17,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                  ),
                  itemCount: filteredDocs.length,

                  itemBuilder: (context, index) {
                    final chat =
                        filteredDocs[index];

                    final data =
                        chat.data()
                            as Map<String, dynamic>;

                    final participants =
                        List<String>.from(
                      data['participants'] ?? [],
                    );

                    final otherUserId =
                        participants.firstWhere(
                      (id) => id != currentUser.uid,
                      orElse: () => '',
                    );

                    if (otherUserId.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return _ChatTile(
                      firestore: _firestore,
                      chatId: chat.id,
                      otherUserId: otherUserId,
                      lastMessage:
                          (data['lastMessage'] ?? '')
                              .toString(),
                      lastMessageTime:
                          data['lastMessageTime']
                              is Timestamp
                          ? data['lastMessageTime']
                              as Timestamp
                          : null,
                      formatTime: _formatTime,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final FirebaseFirestore firestore;
  final String chatId;
  final String otherUserId;
  final String lastMessage;
  final Timestamp? lastMessageTime;
  final String Function(Timestamp?) formatTime;

  const _ChatTile({
    required this.firestore,
    required this.chatId,
    required this.otherUserId,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: firestore
          .collection('users')
          .doc(otherUserId)
          .get(),

      builder: (context, snapshot) {
        String name = 'TalkBee User';
        String email = '';

        if (snapshot.hasData &&
            snapshot.data!.exists) {
          final data =
              snapshot.data!.data()
                  as Map<String, dynamic>;

          name =
              (data['name'] ?? 'TalkBee User')
                  .toString();

          email =
              (data['email'] ?? '').toString();
        }

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 5,
          ),

          leading: CircleAvatar(
            radius: 27,
            backgroundColor:
                Colors.amber.shade200,
            child: Text(
              name.isNotEmpty
                  ? name[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),

          title: Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),

          subtitle: Text(
            lastMessage.isEmpty
                ? email
                : lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          trailing: Text(
            formatTime(lastMessageTime),
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),

          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  name: name,
                  userId: otherUserId,
                  online: false,
                ),
              ),
            );
          },
        );
      },
    );
  }
}