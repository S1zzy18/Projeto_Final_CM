import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/login_screen.dart'; // Importa o ecrã inicial

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyCmbXYLYRNSjg58e1Ou2MMcZMcKC9nEW9Y",
      appId: "1:231398904940:web:b0f882a5181a5059e8f449",
      messagingSenderId: "231398904940",
      projectId: "ghost-specs",
    ),
  );
  
  runApp(const GhostSpecApp());
}

class GhostSpecApp extends StatelessWidget {
  const GhostSpecApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GhostSpec',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.redAccent,
      ),
      home: const LoginScreen(),
    );
  }
}