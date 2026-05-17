import 'dart:async';
import 'login_screen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Variável global para sabermos o carro do utilizador que fez login
String nomeDoCarroUtilizador = "Carro Desconhecido";

// ECRÃ 1: DASHBOARD (TELEMETRIA COORDENADA COM O GPS)
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double speedKmH = 0.0;
  StreamSubscription<Position>? _positionSubscription;
  final List<double> _speedBuffer = [];
  final int _bufferSize = 3;
  double _displaySpeedKmH = 0.0;
  bool isTesting = false;
  bool _manualTestRequested = false;
  int _stationaryReadings = 0; // conta leituras consecutivas com speed == 0
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

    // Configurações otimizadas para Android real para evitar o crash nativo (Signal 3)
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0, // reduzir delay: receber mais updates (0 metros)
    );

    try {
      _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      // Ignora leituras com baixa precisão
      if (position.accuracy != null && position.accuracy > 20.0) {
        return;
      }

      double currentSpeed = position.speed > 0 ? position.speed * 3.6 : 0.0;

      // Buffer para média móvel e reduzir jitter do GPS (menor buffer para menor lag)
      _speedBuffer.add(currentSpeed);
      if (_speedBuffer.length > _bufferSize) _speedBuffer.removeAt(0);
      final avg = _speedBuffer.isEmpty ? 0.0 : (_speedBuffer.reduce((a, b) => a + b) / _speedBuffer.length);

      // Deadzone: evita mostrar pequenas velocidades devido a ruído do GPS
      const double deadzoneKmH = 0.5; // reduzir deadzone para ser mais responsivo
      final filtered = avg < deadzoneKmH ? 0.0 : avg;

      // Contabiliza leituras estacionárias consecutivas (para evitar iniciar teste quando app abre em andamento)
      if (filtered == 0.0) {
        _stationaryReadings = (_stationaryReadings + 1).clamp(0, 10);
      } else {
        _stationaryReadings = 0;
      }

      // Atualiza apenas quando houver alteração significativa para reduzir repaints
      if ((filtered - _displaySpeedKmH).abs() > 0.05) {
        _displaySpeedKmH = filtered;
        setState(() {
          speedKmH = _displaySpeedKmH;
        });
      }

      // Use the filtered speed (avg + deadzone) to decide start/stop of the test
      const double startThresholdKmH = 3.0; // require a small movement to start
      const double finishThresholdKmH = 100.0;
      // Se um teste manual foi pedido, só começa quando partimos de 0
      if (_manualTestRequested) {
        if (!isTesting && filtered >= startThresholdKmH) {
          isTesting = true;
          startTime = DateTime.now();
          elapsedTime = 0.0;
          setState(() {
            testStatus = "0→100 em curso...";
          });
        }
      } else {
        // Auto-test: só iniciar se o carro esteve parado recentemente
        if (!isTesting && _stationaryReadings >= 3 && filtered >= startThresholdKmH) {
          isTesting = true;
          startTime = DateTime.now();
          elapsedTime = 0.0;
          setState(() {
            testStatus = "A medir aceleração...";
          });
        }
      }

      if (isTesting && startTime != null) {
        final now = DateTime.now();
        final difference = now.difference(startTime!).inMilliseconds / 1000;

        // Atualiza o tempo enquanto o teste está a decorrer
        setState(() {
          elapsedTime = difference;
        });

        if (filtered >= finishThresholdKmH) {
          isTesting = false;
          _manualTestRequested = false;
          setState(() {
            testStatus = "Feito! Tempo: ${elapsedTime.toStringAsFixed(2)}s";
          });
          _saveTimeGlobal(elapsedTime);
          startTime = null;
        }
      }

      // após o teste concluído, reinicia o estado quando a velocidade filtrada mantiver 0
      if (!isTesting && _displaySpeedKmH == 0.0 && testStatus.contains("Feito")) {
        setState(() {
          testStatus = "Pronto para arrancar";
          elapsedTime = 0.0;
        });
      }
      }, onError: (error) {
        print("Erro capturado no stream do GPS: $error");
      });
    } catch (e) {
      // Captura erros sincronos ao iniciar o stream (evita crash nativo não tratado)
      print('Falha ao iniciar stream do Geolocator: $e');
    }
  }

  Future<String?> _saveTimeGlobal(double time) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final col = FirebaseFirestore.instance.collection('rankings');
      if (user != null) {
        final q = await col.where('uid', isEqualTo: user.uid).limit(1).get();
        if (q.docs.isNotEmpty) {
          final existing = q.docs.first;
          await col.doc(existing.id).update({
            'email': user.email,
            'carro': nomeDoCarroUtilizador,
            'tempo': time,
            'data': FieldValue.serverTimestamp(),
          });
          print('Ranking atualizado: ${existing.id} (tempo: $time)');
          return existing.id;
        }
      }

      final docRef = await col.add({
        'uid': user?.uid,
        'email': user?.email,
        'carro': nomeDoCarroUtilizador,
        'tempo': time,
        'data': FieldValue.serverTimestamp(),
      });
      print('Ranking gravado: ${docRef.id} (tempo: $time)');
      return docRef.id;
    } catch (e) {
      print("Erro ao enviar dados para o Firestore: $e");
      return null;
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
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20)),
              onPressed: (speedKmH == 0.0 && !isTesting)
                  ? () {
                      setState(() {
                        _manualTestRequested = true;
                        testStatus = 'Botão 0→100 ativado. Arranque para iniciar.';
                      });
                    }
                  : null,
              icon: const Icon(Icons.flag, color: Colors.white),
              label: const Text('0 → 100 (manual)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20)),
              onPressed: () async {
                final docId = await _saveTimeGlobal(elapsedTime);
                final message = docId != null ? 'Gravado: $docId' : 'Erro ao gravar';
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                }
              },
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text('Gravar (debug)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}

// ECRÃ 2: RANKINGS (LEADERBOARD DO FIREBASE)
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
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? "Utilizador";

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
            const Center(child: Icon(Icons.account_circle, size: 100, color: Colors.grey)),
            const SizedBox(height: 10),
            Center(child: Text(userEmail, style: const TextStyle(fontSize: 16, color: Colors.grey))),
            const SizedBox(height: 20),
            const Text('Máquina Ativa:', style: TextStyle(fontSize: 16, color: Colors.grey)),
            Text(nomeDoCarroUtilizador, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 40, color: Colors.grey),
            const Text('Status da Licença:', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 5),
                Text('Categoria B Ativa', style: TextStyle(fontSize: 18)),
              ],
            ),
            const Spacer(), 
            
            // BOTÃO DE LOGOUT SEGURO
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                ),
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                label: const Text(
                  'TERMINAR SESSÃO', 
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (Route<dynamic> route) => false,
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}