import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() =>
      _EditProfileScreenState();
}

class _EditProfileScreenState
    extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _bioController = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  bool _loadingProfile = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  String _photoUrl = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    try {
      final document = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data =
          document.data() ?? <String, dynamic>{};

      _nameController.text =
          (data['name'] ?? user.displayName ?? '')
              .toString();

      _bioController.text =
          (data['bio'] ?? '').toString();

      _photoUrl =
          (data['photoUrl'] ?? '').toString();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to load profile: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    try {
      setState(() {
        _uploadingPhoto = true;
      });

      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (pickedFile == null) {
        return;
      }

      final Uint8List bytes =
          await pickedFile.readAsBytes();

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child('${user.uid}.jpg');

      await storageRef.putData(
        bytes,
        SettableMetadata(
          contentType: 'image/jpeg',
        ),
      );

      final downloadUrl =
          await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'photoUrl': downloadUrl,
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _photoUrl = downloadUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Profile photo updated!',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to upload photo: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final name =
          _nameController.text.trim();

      final bio =
          _bioController.text.trim();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'name': name,
        'bio': bio,
        'photoUrl': _photoUrl,
      }, SetOptions(merge: true));

      await user.updateDisplayName(name);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Profile updated successfully!',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to save profile: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),

        child: Form(
          key: _formKey,

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,

            children: [
              GestureDetector(
                onTap:
                    _uploadingPhoto
                        ? null
                        : _pickAndUploadPhoto,

                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 65,
                      backgroundColor:
                          Colors.amber.shade200,
                      backgroundImage:
                          _photoUrl.isNotEmpty
                              ? NetworkImage(_photoUrl)
                              : null,
                      child: _photoUrl.isEmpty
                          ? const Icon(
                              Icons.person,
                              size: 65,
                              color: Colors.black,
                            )
                          : null,
                    ),

                    if (_uploadingPhoto)
                      const CircularProgressIndicator(),

                    if (!_uploadingPhoto)
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: Container(
                          padding:
                              const EdgeInsets.all(9),
                          decoration:
                              const BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              const Center(
                child: Text(
                  'Tap photo to change',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),
              ),

              const SizedBox(height: 30),

              TextFormField(
                controller: _nameController,
                textCapitalization:
                    TextCapitalization.words,
                decoration:
                    const InputDecoration(
                  labelText: 'Name',
                  prefixIcon:
                      Icon(Icons.person_outline),
                  border:
                      OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null ||
                      value.trim().isEmpty) {
                    return 'Please enter your name';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _bioController,
                maxLines: 3,
                maxLength: 150,
                decoration:
                    const InputDecoration(
                  labelText: 'Bio',
                  hintText:
                      'Tell people something about you',
                  prefixIcon:
                      Icon(Icons.info_outline),
                  border:
                      OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 55,
                child: ElevatedButton(
                  onPressed:
                      _saving
                          ? null
                          : _saveProfile,
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 17,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}