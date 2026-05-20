import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/login_screen.dart'; // Importa o ecrã inicial
import 'screens/main_navigation.dart';
import 'screens/app_screens.dart';
import 'services/preferences_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PreferencesService.init();
  final prefName = PreferencesService.getString('preferred_car_name');
  if (prefName != null && prefName.isNotEmpty) {
    nomeDoCarroUtilizador = prefName;
    debugPrint('Carro preferido carregado: $prefName');
  }
  
  try {
    // Try default initialization which reads native config files
    await Firebase.initializeApp();
  } catch (e) {
    // Fallback to explicit options when native config is not available
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCmbXYLYRNSjg58e1Ou2MMcZMcKC9nEW9Y",
        appId: "1:231398904940:web:b0f882a5181a5059e8f449",
        messagingSenderId: "231398904940",
        projectId: "ghost-specs",
        // Alternate bucket format — some projects use the .appspot.com bucket name
        storageBucket: "ghost-specs.appspot.com",
      ),
    );
  }
  
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
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  User? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      _user = user;
      if (_user != null) {
        // Carrega o nome do carro do utilizador para a variável global
        try {
          final doc = await FirebaseFirestore.instance.collection('utilizadores').doc(_user!.uid).get();
          if (doc.exists && doc.data() != null) {
            nomeDoCarroUtilizador = doc.data()!['carro'] ?? nomeDoCarroUtilizador;
            usernameUtilizador = doc.data()!['username'] ?? usernameUtilizador;
          }
        } catch (e) {
          debugPrint('Erro ao carregar dados iniciais do utilizador: $e');
        }
      }
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_user != null) {
      return const MainNavigationScreen();
    }
    return const LoginScreen();
  }
}