import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<int> _getNextUserId() async {
    final allDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc('All')
        .get();

    if (!allDoc.exists) {
      return 1; // Primeiro usuário
    }

    final data = allDoc.data() as Map<String, dynamic>;
    int maxId = 0;

    data.forEach((key, value) {
      if (key.startsWith('User')) {
        final userId = int.tryParse(key.replaceAll('User', '')) ?? 0;
        if (userId > maxId) {
          maxId = userId;
        }
      }
    });

    return maxId + 1; // Próximo ID disponível
  }

  Future<void> _register() async {
    setState(() => _isLoading = true);
    
    try {
      // 1. Criar usuário no Firebase Auth
      UserCredential userCredential = 
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
      
      String uid = userCredential.user!.uid;
      String nome = _emailController.text.split('@')[0];

      // 2. Obter o próximo ID sequencial
      int nextId = await _getNextUserId();

      // 3. Criar documento do usuário no Firestore
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);
      
      await userDocRef.set({
        'Amigos': [], // Array vazio
        'ID': nextId, // ID sequencial
        'Nome': nome, // Nome extraído do e-mail
        'Hist_Distancia': [], // Array vazio
        'Hist_Nivel': [], // Array vazio
        'Hist_Tempo': [], // Array vazio
        'Hist_Amigos': [], // Array vazio
      });

      // 4. Atualizar o documento "All" com a estrutura especificada
      final allDocRef = FirebaseFirestore.instance.collection('users').doc('All');
      
      await allDocRef.set({
        'User$nextId': [nextId, uid, nome], // Formato: [número, string UID]
      }, SetOptions(merge: true));

      // Sucesso
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cadastro realizado com sucesso!')),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Erro ao cadastrar';
      if (e.code == 'weak-password') {
        errorMessage = 'Senha muito fraca (mínimo 6 caracteres)';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'Este e-mail já está cadastrado';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'E-mail inválido';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no Firestore: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar-se'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isLoading ? null : _register,
                child: _isLoading 
                    ? const CircularProgressIndicator()
                    : const Text('Registrar-se'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}