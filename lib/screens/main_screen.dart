import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xuka/screens/HistoricoScreen.dart';
import 'bikes_screen.dart';
import 'friends_screen.dart';
import 'new_route.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  File? _profileImage;
  final ImagePicker _picker = ImagePicker();
  String _lastDistance = '0 km';
  String _lastInclination = '0°';
  String _lastTime = '0 min';
  String _lastCompanion = 'Ninguém';
  bool _isLoading = true;
  String? _currentUserId;
  int? _currentUserNumberId;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _loadLocalImage();
    _loadUserData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute? route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      _loadUserData();
    }
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    await _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      setState(() {
        _currentUserId = user.uid;
        _currentUsername = user.email?.split('@')[0] ?? '';
      });

      final allDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc('All')
          .get();

      if (allDoc.exists) {
        final allData = allDoc.data() as Map<String, dynamic>;
        
        for (var entry in allData.entries) {
          if (entry.value is List && entry.value.length >= 3 && entry.value[2] == _currentUsername) {
            setState(() {
              _currentUserNumberId = entry.value[0];
              if (entry.value[1] is String) {
                _currentUserId = entry.value[1];
              } else if (entry.value[1] is DocumentReference) {
                _currentUserId = (entry.value[1] as DocumentReference).id;
              }
            });
            break;
          }
        }
      }

      if (_currentUserNumberId != null && _currentUserId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          
          final distances = List.from(userData['Hist_Distancia'] ?? []);
          final inclinations = List.from(userData['Hist_Nivel'] ?? []);
          final times = List.from(userData['Hist_Tempo'] ?? []);
          final companions = List.from(userData['Hist_Amigos'] ?? []);

          setState(() async {
            if (distances.isNotEmpty) {
              _lastDistance = '${distances.last} km';
            }
            if (inclinations.isNotEmpty) {
              _lastInclination = '${inclinations.last}°';
            }
            if (times.isNotEmpty) {
              _lastTime = '${times.last} min';
            }
            if (companions.isNotEmpty) {
              final lastCompanionId = companions.last;
              try {
                final docSnapshot = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(lastCompanionId)
                    .get();

                if (docSnapshot.exists) {
                  final data = docSnapshot.data() as Map<String, dynamic>;
                  setState(() {
                    _lastCompanion = data['Nome'] ?? 'Desconhecido';
                  });
                } else {
                  setState(() {
                    _lastCompanion = 'Companheiro não encontrado';
                  });
                }
              } catch (e) {
                print('Erro ao buscar companheiro: $e');
                setState(() {
                  _lastCompanion = 'Erro ao buscar companheiro';
                });
              }
            }

            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Erro ao buscar dados do usuário: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLocalImage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final imagePath = '${directory.path}/profile_image.jpg';
      if (await File(imagePath).exists()) {
        setState(() => _profileImage = File(imagePath));
      }
    } catch (e) {
      print('Erro ao carregar imagem local: $e');
    }
  }

  Future<void> _saveImageLocally(File image) async {
    final directory = await getApplicationDocumentsDirectory();
    final imagePath = '${directory.path}/profile_image.jpg';
    await image.copy(imagePath);
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      final imageFile = File(pickedFile.path);
      await _saveImageLocally(imageFile);
      setState(() => _profileImage = imageFile);
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera),
                title: const Text('Tirar foto'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Escolher da galeria'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tela Principal')),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/sc2.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 3,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _showImagePickerOptions,
                      child: Container(
                        width: 80,
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                        child: _profileImage != null
                            ? ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  bottomLeft: Radius.circular(8),
                                ),
                                child: Image.file(_profileImage!, fit: BoxFit.cover),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt, 
                                      size: 30,
                                      color: Colors.white),
                                  SizedBox(height: 4),
                                  Text('Adicionar foto',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white
                                      )),
                                ],
                              ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        padding: const EdgeInsets.only(left: 12, top: 8),
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Bem-vindo, $_currentUsername!',
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 3,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15.0),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Dados da Última Rota',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Distância',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      _lastDistance,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Inclinação',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      _lastInclination,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Tempo',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      _lastTime,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            Text(
                              _lastCompanion == 'Ninguém' 
                                  ? 'Sozinho no percurso'
                                  : 'Junto com: $_lastCompanion',
                              style: const TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),

            // NOVO BOTÃO HISTÓRICO ADICIONADO AQUI
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HistoricoScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 148, 113, 68),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 5,
                  ),
                  child: const Text(
                    'Histórico',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 150.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      SizedBox(
                        width: 150,
                        child: ElevatedButton(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const BikesScreen()),
                            );
                            _loadUserData();
                          },
                          child: const Text('Bicicleta'),
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: ElevatedButton(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const FriendsScreen()),
                            );
                            _loadUserData();
                          },
                          child: const Text('Amigos'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: 350,
                    child: ElevatedButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => NewRoute()),
                        );
                        _loadUserData();
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Novo Percurso'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}