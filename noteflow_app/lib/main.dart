import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';

bool firebaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyDCeLw9A84GllUf5-Av7SyHaSS9Cb8TAwA',
        authDomain: 'noteflow-da76f.firebaseapp.com',
        projectId: 'noteflow-da76f',
        storageBucket: 'noteflow-da76f.firebasestorage.app',
        messagingSenderId: '653749509123',
        appId: '1:653749509123:web:350af7fbbd170cde6f8236',
        measurementId: 'G-J4NSS2BLSB',
      ),
    );
    firebaseInitialized = true;
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
    firebaseInitialized = false;
  }

  runApp(
    const ProviderScope(
      child: NoteFlowApp(),
    ),
  );
}
