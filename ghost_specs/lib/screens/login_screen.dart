import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main_navigation.dart';
import 'app_screens.dart'; // Para atualizar a variável nomeDoCarroUtilizador
import '../services/preferences_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailLoginController = TextEditingController();
  final _passwordLoginController = TextEditingController();

  final _emailRegistoController = TextEditingController();
  final _passwordRegistoController = TextEditingController();
  final _carRegistoController = TextEditingController();
  final _usernameRegistoController = TextEditingController();

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    final prefEmail = PreferencesService.getString('preferred_email'); // Tenta carregar o email preferido do utilizador
    if (prefEmail != null && prefEmail.isNotEmpty) {
      _emailLoginController.text = prefEmail;
    }
  }

  Future<void> _fazerLogin() async {
    if (_emailLoginController.text.isEmpty || _passwordLoginController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preenche o email e a password, chefe!')));
      return;
    }

    setState(() => isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailLoginController.text.trim(),
        password: _passwordLoginController.text.trim(),
      );

      final userId = FirebaseAuth.instance.currentUser?.uid;
      final userDoc = await FirebaseFirestore.instance.collection('utilizadores').doc(userId).get();
      
      if (userDoc.exists && userDoc.data() != null) {
        nomeDoCarroUtilizador = userDoc.data()!['carro'] ?? "Opel Corsa GS";
        usernameUtilizador = userDoc.data()!['username'] ?? "Utilizador";
      } else {
        nomeDoCarroUtilizador = "Opel Corsa GS";
      }

      // Save email locally for auto-fill on login
      try {
        await PreferencesService.setString('preferred_email', _emailLoginController.text.trim());
      } catch (_) {}

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro no Login: ${e.message}')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _criarConta() async {
    if (_emailRegistoController.text.isEmpty || _passwordRegistoController.text.isEmpty || _carRegistoController.text.isEmpty || _usernameRegistoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preenche todos os campos para o registo!')));
      return;
    }

    setState(() => isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailRegistoController.text.trim(),
        password: _passwordRegistoController.text.trim(),
      );

      nomeDoCarroUtilizador = _carRegistoController.text.trim();
      usernameUtilizador = _usernameRegistoController.text.trim();

      await FirebaseFirestore.instance.collection('utilizadores').doc(credential.user?.uid).set({
        'email': _emailRegistoController.text.trim(),
        'carro': nomeDoCarroUtilizador,
        'username': usernameUtilizador,
      });

      // (Do not save email on registration; only save on login for autofill)

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro no Registo: ${e.message}')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GHOSTSPEC', style: TextStyle(letterSpacing: 4, color: Colors.redAccent, fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.black,
          bottom: const TabBar(
            indicatorColor: Colors.redAccent,
            labelColor: Colors.redAccent,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'LOGIN', icon: Icon(Icons.login)),
              Tab(text: 'REGISTO', icon: Icon(Icons.person_add)),
            ],
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
            : TabBarView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(controller: _emailLoginController, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
                        const SizedBox(height: 16),
                        TextField(controller: _passwordLoginController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 16)),
                          onPressed: _fazerLogin,
                          child: const Text('ENTRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 40),
                          TextField(controller: _emailRegistoController, decoration: const InputDecoration(labelText: 'Email de Registo', border: OutlineInputBorder())),
                          const SizedBox(height: 16),
                          TextField(controller: _passwordRegistoController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                          const SizedBox(height: 16),
                          TextField(controller: _carRegistoController, decoration: const InputDecoration(labelText: 'O teu Carro (ex: Opel Corsa GS)', border: OutlineInputBorder())),
                          const SizedBox(height: 16),
                          TextField(controller: _usernameRegistoController, decoration: const InputDecoration(labelText: 'Username público (aparece no ranking)', border: OutlineInputBorder())),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 16)),
                            onPressed: _criarConta,
                            child: const Text('CRIAR CONTA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  void dispose() {
    _emailLoginController.dispose();
    _passwordLoginController.dispose();
    _emailRegistoController.dispose();
    _passwordRegistoController.dispose();
    _carRegistoController.dispose();
    _usernameRegistoController.dispose();
    super.dispose();
  }
}