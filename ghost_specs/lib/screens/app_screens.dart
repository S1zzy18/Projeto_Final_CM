import 'dart:async';
import 'login_screen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

// Variável global para sabermos o carro do utilizador que fez login
String nomeDoCarroUtilizador = "Carro Desconhecido";
// Username público do utilizador (para mostrar no ranking)
String usernameUtilizador = "Utilizador";

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
  double _sessionMaxSpeed = 0.0; // armazena velocidade máxima durante a sessão até parar
  double _lastSavedBestSpeed = 0.0; // último valor guardado no server para evitar muitas escritas

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
      if (position.accuracy > 20.0) {
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

      // Atualiza velocidade máxima da sessão e grava em background quando excede o último guardado
      if (filtered > _sessionMaxSpeed) {
        _sessionMaxSpeed = filtered;

        const double saveThreshold = 1.0; // só grava se aumentou >= 1 km/h desde o último save
        if (_sessionMaxSpeed - _lastSavedBestSpeed >= saveThreshold) {
          final toSave = _sessionMaxSpeed;
          _lastSavedBestSpeed = toSave;
          // upsert em max_speeds (mantém apenas 1 registo por utilizador)
          _upsertMaxSpeed(toSave);
        }
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

      // Quando o carro para: reinicia a sessão e o marcador de último guardado
      if (_displaySpeedKmH == 0.0 && _sessionMaxSpeed > 0.0 && _stationaryReadings >= 3) {
        _sessionMaxSpeed = 0.0;
        _lastSavedBestSpeed = 0.0;
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
      // fetch user profile data (photoUrl)
      DocumentSnapshot<Map<String, dynamic>>? userDoc;
      String? photoUrl;
      if (user != null) {
        userDoc = await FirebaseFirestore.instance.collection('utilizadores').doc(user.uid).get();
        if (userDoc.exists && userDoc.data() != null) photoUrl = userDoc.data()!['photoUrl'] as String?;
      }
      if (user != null) {
        final q = await col.where('uid', isEqualTo: user.uid).limit(1).get();
        if (q.docs.isNotEmpty) {
          final existing = q.docs.first;
          await col.doc(existing.id).update({
              'email': user.email,
              'username': usernameUtilizador,
              'photoUrl': photoUrl,
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
          'username': usernameUtilizador,
          'photoUrl': photoUrl,
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

  // _saveMaxSpeed removed; using background-saving helpers instead.

  // Upsert a single document in `max_speeds` per user: update existing or create new.
  Future<void> _upsertMaxSpeed(double velocidade) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      // fetch user profile data (photoUrl)
      final userDoc = await FirebaseFirestore.instance.collection('utilizadores').doc(user.uid).get();
      String? photoUrl;
      if (userDoc.exists && userDoc.data() != null) photoUrl = userDoc.data()!['photoUrl'] as String?;
      final col = FirebaseFirestore.instance.collection('max_speeds');
      final q = await col.where('uid', isEqualTo: user.uid).get();
      double current = 0.0;
      if (q.docs.isNotEmpty) {
        // Determine the current saved max (take the maximum across any duplicates)
        for (var d in q.docs) {
          try {
            final v = (d.data()['velocidade'] ?? 0) as num;
            if (v > current) current = v.toDouble();
          } catch (_) {}
        }

        // Only update if the new value is greater than current
        if (velocidade > current) {
          final firstDoc = q.docs.first;
          await col.doc(firstDoc.id).update({
            'velocidade': velocidade,
            'username': usernameUtilizador,
            'photoUrl': photoUrl,
            'carro': nomeDoCarroUtilizador,
            'email': user.email,
            'data': FieldValue.serverTimestamp(),
          });
        }

        // Delete any additional docs for this uid, keep the first one
        for (var i = 1; i < q.docs.length; i++) {
          try {
            await col.doc(q.docs[i].id).delete();
          } catch (_) {}
        }
      } else {
        // No existing doc, create one
        await col.add({
          'uid': user.uid,
          'email': user.email,
          'username': usernameUtilizador,
          'photoUrl': photoUrl,
          'carro': nomeDoCarroUtilizador,
          'velocidade': velocidade,
          'data': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // ignore background errors
    }
  }

  // removed user_max_speeds maintenance — using only `max_speeds` collection per-user

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
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
                  onPressed: () async {
                    await _forceSetUserMax50();
                  },
                  icon: const Icon(Icons.bug_report, color: Colors.white),
                  label: const Text('Debug: set max 50', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
                  onPressed: () async {
                    await _forceSetUserMax70();
                  },
                  icon: const Icon(Icons.bug_report, color: Colors.white),
                  label: const Text('Debug: set max 70', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _forceSetUserMax50() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum utilizador ligado')));
        return;
      }

      // Atualiza apenas se for melhor que o existente
      await _upsertMaxSpeed(50.0);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debug: tentativa de definir velocidade máxima para 50 km/h (atualiza só se for melhor)')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro debug: $e')));
    }
  }

  Future<void> _forceSetUserMax70() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum utilizador ligado')));
        return;
      }

      // Atualiza apenas se for melhor que o existente
      await _upsertMaxSpeed(70.0);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debug: tentativa de definir velocidade máxima para 70 km/h (atualiza só se for melhor)')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro debug: $e')));
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}

// ECRÃ 2: RANKINGS (LEADERBOARD DO FIREBASE)
class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  bool _showMaxSpeed = false;

  @override
  Widget build(BuildContext context) {
    final title = _showMaxSpeed ? 'RANKING VELOCIDADE MÁXIMA' : 'RANKING 0-100';
    final stream = _showMaxSpeed
        ? FirebaseFirestore.instance.collection('max_speeds').orderBy('velocidade', descending: true).snapshots()
        : FirebaseFirestore.instance.collection('rankings').orderBy('tempo', descending: false).snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: Colors.grey[900],
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                const Text('0-100', style: TextStyle(color: Colors.grey)),
                Switch(
                  value: _showMaxSpeed,
                  onChanged: (v) => setState(() => _showMaxSpeed = v),
                  activeThumbColor: Colors.redAccent,
                ),
                const Text('Vel. Máx', style: TextStyle(color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Erro ao carregar dados'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.redAccent));

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('Nenhum registo ainda.'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              Widget leadingWidget;
              final photo = (data['photoUrl'] ?? '') as String;
              if (photo.isNotEmpty) {
                leadingWidget = CircleAvatar(backgroundImage: NetworkImage(photo));
              } else {
                leadingWidget = CircleAvatar(
                  backgroundColor: index == 0 ? Colors.amber : (index == 1 ? Colors.grey : Colors.brown),
                  child: Text('${index + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                );
              }
              return ListTile(
                leading: leadingWidget,
                title: GestureDetector(
                  onTap: () {
                    final carro = data['carro'] ?? 'Desconhecido';
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(data['username'] ?? (carro)),
                        content: Text('Carro: $carro'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
                        ],
                      ),
                    );
                  },
                  child: Text(data['username'] ?? data['carro'] ?? 'Desconhecido', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                trailing: _showMaxSpeed
                    ? Text('${(data['velocidade'] ?? 0).toStringAsFixed(1)} km/h', style: const TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold))
                    : Text('${(data['tempo'] ?? 0).toStringAsFixed(2)}s', style: const TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
              );
            },
          );
        },
      ),
    );
  }
}

// ECRÃ 3: PERFIL DO UTILIZADOR
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _photoUrl;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('utilizadores').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        setState(() {
          _photoUrl = doc.data()!['photoUrl'] as String?;
        });
      }
    } on FirebaseException catch (e) {
      // Permission denied or other Firestore access error - don't crash the UI.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar perfil: [${e.code}] ${e.message}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar perfil: $e')));
      }
    }
  }

  Future<void> _pickAndUploadProfileImage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 80);
      if (picked == null) return;

      final file = File(picked.path);
      final ref = FirebaseStorage.instance.ref().child('profile_photos').child('${user.uid}.jpg');
      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask.whenComplete(() {});
      final url = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('utilizadores').doc(user.uid).update({'photoUrl': url});

      setState(() {
        _photoUrl = url;
      });

      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto de perfil atualizada.')));
    } on FirebaseException catch (e) {
      // Provide clearer error messages depending on the Storage error code
      final code = e.code;
      final msg = e.message ?? e.toString();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar imagem: [$code] $msg')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar imagem: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final userDisplayName = (usernameUtilizador.isNotEmpty && usernameUtilizador != "Utilizador")
        ? usernameUtilizador
        : (FirebaseAuth.instance.currentUser?.email ?? "Utilizador");

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
            Center(
              child: GestureDetector(
                onTap: _pickAndUploadProfileImage,
                child: _photoUrl != null && _photoUrl!.isNotEmpty
                    ? CircleAvatar(radius: 50, backgroundImage: NetworkImage(_photoUrl!))
                    : const CircleAvatar(radius: 50, child: Icon(Icons.account_circle, size: 80, color: Colors.grey)),
              ),
            ),
            const SizedBox(height: 10),
            Center(child: Text(userDisplayName, style: const TextStyle(fontSize: 16, color: Colors.grey))),
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