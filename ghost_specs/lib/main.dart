import 'package:flutter/material.dart'; // Importa o Flutter Material Design
import 'package:firebase_core/firebase_core.dart'; // Importa o Firebase Core para inicialização
import 'package:firebase_auth/firebase_auth.dart';  // Importa o Firebase Authentication para autenticação de utilizadores
import 'package:cloud_firestore/cloud_firestore.dart'; // Importa o Cloud Firestore para acesso à base de dados
import 'screens/login_screen.dart'; // Importa o ecrã inicial
import 'screens/main_navigation.dart'; // Importa o ecrã de navegação principal
import 'screens/app_screens.dart'; // Importa outros ecrãs da aplicação
import 'services/preferences_service.dart'; // Importa o serviço de preferências para armazenamento local

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Garante que o Flutter esteja inicializado antes de executar
  await PreferencesService.init();
  debugPrint('PreferencesService inicializado');
  
  try {
    // Try default initialization which reads native config files
    await Firebase.initializeApp();
  } catch (e) {
    // Se falhar, tenta inicialização manual com opções explícitas (útil para desenvolvimento local ou se os arquivos de configuração estiverem ausentes)
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCmbXYLYRNSjg58e1Ou2MMcZMcKC9nEW9Y",
        appId: "1:231398904940:web:b0f882a5181a5059e8f449",
        messagingSenderId: "231398904940",
        projectId: "ghost-specs",
        // Tentar adicionar storageBucket para evitar erros relacionados a isso, mesmo que não seja usado diretamente
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