import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  List<Map<String, dynamic>> _historicoRotas = [];
  bool _isLoading = true;
  String? _currentUserId;
  int? _currentUserNumberId;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
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

      if (_currentUserId != null) {
        await _fetchHistoricoRotas();
      }
    } catch (e) {
      print('Erro ao carregar dados do usuário: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchHistoricoRotas() async {
    try {
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

        List<Map<String, dynamic>> rotas = [];

        // Determinar o número de rotas pelo maior array
        int numRotas = [
          distances.length,
          inclinations.length,
          times.length,
          companions.length
        ].reduce((a, b) => a > b ? a : b);

        for (int i = 0; i < numRotas; i++) {
          String nomeCompanheiro = 'Ninguém';
          
          if (i < companions.length && companions[i] != null && companions[i].isNotEmpty) {
            try {
              final companionDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(companions[i])
                  .get();
              
              if (companionDoc.exists) {
                nomeCompanheiro = companionDoc.data()?['Nome'] ?? 'Desconhecido';
              }
            } catch (e) {
              print('Erro ao buscar companheiro: $e');
            }
          }

          rotas.add({
            'distancia': i < distances.length ? distances[i] : '0',
            'inclinacao': i < inclinations.length ? inclinations[i] : '0',
            'tempo': i < times.length ? times[i] : '0',
            'companheiro': nomeCompanheiro,
            'index': i,
          });
        }

        // Ordenar do mais recente para o mais antigo
        rotas.sort((a, b) => b['index'].compareTo(a['index']));

        setState(() {
          _historicoRotas = rotas;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Erro ao buscar histórico de rotas: $e');
      setState(() => _isLoading = false);
    }
  }

  Widget _buildRotaCard(Map<String, dynamic> rota) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dados da Rota',
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
                        '${rota['distancia']} km',
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
                        '${rota['inclinacao']}°',
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
                        '${rota['tempo']} min',
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
                rota['companheiro'] == 'Ninguém'
                    ? 'Sozinho no percurso'
                    : 'Junto com: ${rota['companheiro']}',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Rotas'),
        backgroundColor: const Color.fromARGB(255, 148, 113, 68),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/sc2.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _historicoRotas.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhuma rota registrada ainda',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 20, bottom: 20),
                    itemCount: _historicoRotas.length,
                    itemBuilder: (context, index) {
                      return _buildRotaCard(_historicoRotas[index]);
                    },
                  ),
      ),
    );
  }
}