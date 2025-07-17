import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final TextEditingController _friendIdController = TextEditingController();
  List<Map<String, dynamic>> _friendsList = [];
  bool _isLoading = true;
  bool _isAddingFriend = false;
  String? _currentUserId;
  int? _currentUserNumberId;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserAndFriends();
  }

  Future<void> _loadCurrentUserAndFriends() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      _currentUserId = user.uid;
      _currentUsername = user.email?.split('@')[0] ?? '';

      // 1. Encontrar nosso número ID no documento All
      final allDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc('All')
          .get();

      if (allDoc.exists) {
        final allData = allDoc.data() as Map<String, dynamic>;
        
        // Procurar nosso username no documento All
        for (var entry in allData.entries) {
          if (entry.value is List && entry.value.length >= 3 && entry.value[2] == _currentUsername) {
            _currentUserNumberId = entry.value[0];
            
            // Obter o userID (pode ser string ou DocumentReference)
            if (entry.value[1] is String) {
              _currentUserId = entry.value[1];
            } else if (entry.value[1] is DocumentReference) {
              _currentUserId = (entry.value[1] as DocumentReference).id;
            }
            break;
          }
        }
      }

      // 2. Carregar nossa lista de amigos
      if (_currentUserNumberId != null && _currentUserId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .get();

        if (userDoc.exists) {
          final friendsRefs = userDoc.data()?['Amigos'] ?? [];
          
          // Buscar detalhes de cada amigo
          List<Map<String, dynamic>> friendsDetails = [];
          for (var friendRef in friendsRefs) {
            String friendId = friendRef is DocumentReference 
                ? friendRef.id 
                : friendRef.toString().split('/').last;
            
            // Buscar o documento do amigo para pegar o nome e número ID
            final friendDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(friendId)
                .get();
            
            if (friendDoc.exists) {
              // Buscar o número ID do amigo no documento All
              int? friendNumberId = await _getUserNumberId(friendId);
              friendsDetails.add({
                'id': friendId,
                'name': friendDoc.data()?['Nome'] ?? 'Amigo sem nome',
                'numberId': friendNumberId ?? 0,
              });
            }
          }

          setState(() {
            _friendsList = friendsDetails;
            _isLoading = false;
          });
          return;
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar amigos: $e')),
      );
    }
  }

  Future<int?> _getUserNumberId(String userId) async {
    final allDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc('All')
        .get();

    if (allDoc.exists) {
      final allData = allDoc.data() as Map<String, dynamic>;
      for (var entry in allData.entries) {
        if (entry.value is List && entry.value.length >= 2) {
          // Verifica se o userID corresponde (pode ser string ou DocumentReference)
          bool match = false;
          if (entry.value[1] is String && entry.value[1] == userId) {
            match = true;
          } else if (entry.value[1] is DocumentReference && 
              (entry.value[1] as DocumentReference).id == userId) {
            match = true;
          }
          
          if (match) {
            return entry.value[0];
          }
        }
      }
    }
    return null;
  }

  Future<void> _addFriend() async {
    if (_friendIdController.text.isEmpty || _currentUserId == null || _currentUserNumberId == null) return;
    
    setState(() => _isAddingFriend = true);
    try {
      final friendNumberId = int.tryParse(_friendIdController.text.trim());
      if (friendNumberId == null) throw Exception('ID inválido');

      // 1. Encontrar o UserID correspondente ao número no documento All
      final allDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc('All')
          .get();

      String? friendUserId;
      if (allDoc.exists) {
        final allData = allDoc.data() as Map<String, dynamic>;
        for (var entry in allData.entries) {
          if (entry.value is List && entry.value.length >= 1 && entry.value[0] == friendNumberId) {
            // Obter o userID (pode ser string ou DocumentReference)
            if (entry.value[1] is String) {
              friendUserId = entry.value[1];
            } else if (entry.value[1] is DocumentReference) {
              friendUserId = (entry.value[1] as DocumentReference).id;
            }
            break;
          }
        }
      }

      if (friendUserId == null) {
        throw Exception('Amigo não encontrado');
      }

      // 2. Adicionar referência ao amigo
      final friendRef = FirebaseFirestore.instance
          .collection('users')
          .doc(friendUserId);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .update({
            'Amigos': FieldValue.arrayUnion([friendRef])
          });

      // 3. Recarregar lista
      await _loadCurrentUserAndFriends();
      
      _friendIdController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amigo adicionado com sucesso!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao adicionar amigo: $e')),
      );
    } finally {
      setState(() => _isAddingFriend = false);
    }
  }

  @override
  void dispose() {
    _friendIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amigos'),
      ),
      body: Stack(
        children: [
          /* Background */
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('assets/images/sc2.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.5),
                  BlendMode.dstATop,
                ),
              ),
            ),
          ),
          
          /* Conteúdo */
          Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _friendsList.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhum amigo adicionado ainda',
                              style: TextStyle(fontSize: 18, color: Colors.white),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: _friendsList.length,
                            itemBuilder: (context, index) {
                              final friend = _friendsList[index];
                              return Container(
                                height: 90,
                                margin: const EdgeInsets.only(bottom: 10),
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
                                    // Parte colorida com ID
                                    Container(
                                      width: 80,
                                      decoration: BoxDecoration(
                                        color: Colors.primaries[friend['numberId'] % Colors.primaries.length],
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(8),
                                          bottomLeft: Radius.circular(8),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          friend['numberId'].toString(),
                                          style: const TextStyle(
                                            fontSize: 24,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    
                                    // Parte branca com informações
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.only(left: 12, top: 8),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.only(
                                            topRight: Radius.circular(8),
                                            bottomRight: Radius.circular(8),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              friend['name'],
                                              style: const TextStyle(
                                                fontSize: 18,
                                                color: Colors.black,
                                              ),
                                            ),
                                            const Text(
                                              '🚴‍♂️',
                                              style: TextStyle(fontSize: 20),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              
              // Área para adicionar amigos
              Container(
                padding: const EdgeInsets.all(20),
                color: Colors.white.withOpacity(0.8),
                child: Column(
                  children: [
                    TextField(
                      controller: _friendIdController,
                      decoration: const InputDecoration(
                        labelText: 'ID do Amigo (número)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isAddingFriend ? null : _addFriend,
                      child: _isAddingFriend
                          ? const CircularProgressIndicator()
                          : const Text('Adicionar Amigo'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}