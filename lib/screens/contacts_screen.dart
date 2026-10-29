import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_screen.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .orderBy('name')
            .snapshots(),

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Something went wrong:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No TalkBee users found.',
                style: TextStyle(fontSize: 18),
              ),
            );
          }

          final users = snapshot.data!.docs;

          final otherUsers = users.where((doc) {
            return doc.id != currentUser?.uid;
          }).toList();

          if (otherUsers.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 80,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'No other TalkBee users yet.',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: otherUsers.length,

            itemBuilder: (context, index) {
              final user = otherUsers[index];

              final data =
                  user.data() as Map<String, dynamic>;

              final name = data['name'] ?? 'TalkBee User';
              final email = data['email'] ?? '';
              final photoUrl =
                    (data['photoUrl'] ?? '').toString();

              return ListTile(
                leading: CircleAvatar(
                        backgroundColor: Colors.amber.shade200,
                        backgroundImage: photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl.isEmpty
                            ? Text(
                                name.toString().isNotEmpty
                                    ? name.toString()[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                ),
                                )
                            : null,
                        ),

                title: Text(
                  name.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),

                subtitle: Text(
                  email.toString(),
                ),

                trailing: const Icon(
                  Icons.chat_bubble_outline,
                ),

                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        name: name.toString(),
                        userId: user.id,
                        online: false,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}