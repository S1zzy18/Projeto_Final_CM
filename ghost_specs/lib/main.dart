import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
      home: const MainNavigationScreen(),
    );
  }
}

// Controla a navegação entre os 3 ecrãs
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const RankingsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        backgroundColor: Colors.grey[950],
        selectedItemColor: Colors.redAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.speed), label: 'Telemetria'),
          BottomNavigationBarItem(icon: Icon(Icons.emoji_events), label: 'Rankings'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

// ECRÃ 1: DASHBOARD (TELEMETRIA)
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double speedKmH = 0.0;
  bool isTesting = false;
  DateTime? startTime;
  double elapsedTime = 0.0;
  String testStatus = "Pronto para arrancar";

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  Future<void> _startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((Position position) {
      double currentSpeed = position.speed > 0 ? position.speed * 3.6 : 0.0;

      setState(() {
        speedKmH = currentSpeed;
      });

      if (!isTesting && currentSpeed > 0.5) {
        isTesting = true;
        startTime = DateTime.now();
        setState(() {
          testStatus = "A medir aceleração...";
        });
      } else if (isTesting && startTime != null) {
        final now = DateTime.now();
        final difference = now.difference(startTime!).inMilliseconds / 1000;
        
        setState(() {
          elapsedTime = difference;
        });

        if (currentSpeed >= 100.0) {
          isTesting = false;
          setState(() {
            testStatus = "Feito! Tempo: ${elapsedTime.toStringAsFixed(2)}s";
          });
          _saveTimeGlobal(elapsedTime);
          startTime = null;
        }
      }

      if (!isTesting && currentSpeed == 0.0 && testStatus.contains("Feito")) {
        setState(() {
          testStatus = "Pronto para arrancar";
          elapsedTime = 0.0;
        });
      }
    });
  }

  Future<void> _saveTimeGlobal(double time) async {
    try {
      await FirebaseFirestore.instance.collection('rankings').add({
        'carro': 'Opel Corsa GS',
        'tempo': time,
        'data': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Erro ao enviar dados: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GHOSTSPEC', style: TextStyle(letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: Colors.grey[900],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(testStatus, style: const TextStyle(fontSize: 20, color: Colors.redAccent, fontWeight: FontWeight.w500)),
            const SizedBox(height: 20),
            Text('${speedKmH.toStringAsFixed(1)} km/h', style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 10),
            Text('Tempo: ${elapsedTime.toStringAsFixed(2)}s', style: TextStyle(fontSize: 30, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }
}

// ECRÃ 2: RANKINGS (Puxa os dados direto do Firebase Firestore)
class RankingsScreen extends StatelessWidget {
  const RankingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LEADERBOARD GLOBAL', style: TextStyle(letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: Colors.grey[900],
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Ordena pelo menor tempo (mais rápido primeiro)
        stream: FirebaseFirestore.instance.collection('rankings').orderBy('tempo', descending: false).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Erro ao carregar dados'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.redAccent));

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) return const Center(child: Text('Nenhum tempo registado ainda.'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: index == 0 ? Colors.amber : (index == 1 ? Colors.grey : Colors.brown),
                  child: Text('${index + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
                title: Text(data['carro'] ?? 'Desconhecido', style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text('${data['tempo'].toStringAsFixed(2)}s', style: const TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
              );
            },
          );
        },
      ),
    );
  }
}

// ECRÃ 3: PERFIL DO UTILIZADOR
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PERFIL DO CONDUTOR', style: TextStyle(letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: Colors.grey[900],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Icon(Icons.account_circle, size: 100, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            const Text('Máquina:', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const Text('Opel Corsa GS (145cv)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 40, color: Colors.grey),
            const Text('Modo Ativo:', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const Text('Performance / Económico', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            const Text('Status da Licença:', style: TextStyle(fontSize: 16, color: Colors.grey)),
            Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 5),
                Text('Categoria B Ativa', style: TextStyle(fontSize: 18)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}