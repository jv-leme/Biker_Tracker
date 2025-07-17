import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class NewRoute extends StatefulWidget {
  const NewRoute({super.key});

  @override
  State<NewRoute> createState() => _NewRouteState();
}

class _NewRouteState extends State<NewRoute> with WidgetsBindingObserver {
  bool _isConnected = false;
  bool _isScanning = false;
  bool _routeStarted = false;
  BluetoothConnection? _connection;
  BluetoothDevice? _device;
  List<BluetoothDevice> _devices = [];
  
  // Route data
  Duration _elapsedTime = Duration.zero;
  double _currentInclination = 0.0;
  double _medInclination = 0.0;
  double _maxInclination = 0.0;
  late DateTime _routeStartTime;
  bool _isTimerRunning = false;
  
  // Location data
  Position? _initialPosition;
  Position? _currentPosition;
  double _distance = 0.0;
  StreamSubscription<Position>? _positionStreamSubscription;
  
  // Firebase
  String? _currentUserId;
  int? _currentUserNumberId;
  String? _currentUsername;
  
  // Friends data
  List<Map<String, dynamic>> _friendsList = [];
  String? _selectedFriendId;
  String? _selectedFriendName;
  bool _isLoadingFriends = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBluetoothState();
    _loadUserData();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _connection?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _routeStarted) {
      setState(() {
        _elapsedTime = DateTime.now().difference(_routeStartTime);
      });
    }
  }

  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled')),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied')),
        );
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permissions are permanently denied')),
      );
      return false;
    }
    
    return true;
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
        await _loadFriendsList();
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _loadFriendsList() async {
    try {
      setState(() => _isLoadingFriends = true);
      
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();

      if (userDoc.exists) {
        final friendsRefs = userDoc.data()?['Amigos'] as List<dynamic>? ?? [];
        
        List<Map<String, dynamic>> friendsDetails = [];
        
        for (var friendRef in friendsRefs) {
          String friendId = friendRef is DocumentReference 
              ? friendRef.id 
              : friendRef.toString();

          final friendDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(friendId)
              .get();
          
          if (friendDoc.exists) {
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
          if (friendsDetails.isNotEmpty) {
            _selectedFriendId = friendsDetails.first['id'];
            _selectedFriendName = friendsDetails.first['name'];
          }
          _isLoadingFriends = false;
        });
      } else {
        setState(() => _isLoadingFriends = false);
      }
    } catch (e) {
      print('Error loading friends list: $e');
      setState(() => _isLoadingFriends = false);
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

  Future<void> _checkBluetoothState() async {
    try {
      bool? isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      if (!isEnabled!) {
        await FlutterBluetoothSerial.instance.requestEnable();
      }
    } catch (e) {
      print("Bluetooth error: $e");
    }
  }

  Future<void> _scanAndConnect() async {
    setState(() {
      _isScanning = true;
      _devices = [];
    });

    try {
      FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
        if (result.device != null && !_devices.contains(result.device)) {
          setState(() {
            _devices.add(result.device!);
          });
        }
      });

      await Future.delayed(const Duration(seconds: 5));

      _device = _devices.firstWhere(
        (device) => device.name?.startsWith("ESP32") ?? false,
        orElse: () => _devices.isNotEmpty ? _devices.first : BluetoothDevice(address: ''),
      );

      if (_device != null && _device!.name != null) {
        _connection = await BluetoothConnection.toAddress(_device!.address);
        
        setState(() {
          _isConnected = true;
          _isScanning = false;
        });

        // Envia o ID do usuário assim que a conexão é estabelecida
        if (_currentUserNumberId != null) {
          await _sendCommand("NOVOID:${_currentUserNumberId}");
        }

        _connection!.input!.listen(_handleIncomingData).onDone(() {
          setState(() {
            _isConnected = false;
            _routeStarted = false;
            _stopTimer();
          });
        });
      } else {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No ESP32 device found")),
        );
      }
    } catch (e) {
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connection failed: $e")),
      );
    }
  }

  void _handleIncomingData(Uint8List data) {
    String incoming = String.fromCharCodes(data);
    print("Received: $incoming");
    
    if (!incoming.contains('\n')) {
      return;
    }

    incoming.split('\n').forEach((line) {
      if (line.startsWith("INCLINATION_ATUAL:")) {
        try {
          double newInclination = double.parse(line.substring(18).trim());
          setState(() {
            _currentInclination = newInclination;
            if (newInclination > _maxInclination) {
              _maxInclination = newInclination;
            }
          });
        } catch (e) {
          print("Error parsing inclination: $e");
        }
      }
      else if (line.startsWith("INCLINATION_MED:")) {
        try {
          double medInclination = double.parse(line.substring(16).trim());
          setState(() {
            _medInclination = medInclination;
          });
        } catch (e) {
          print("Error parsing inclination: $e");
        }
      }
    });
  }

  void _startRoute() async {
    if (!_isConnected) return;
    
    bool hasPermission = await _checkLocationPermission();
    if (!hasPermission) return;
    
    try {
      _initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        if (_initialPosition != null) {
          final newDistance = Geolocator.distanceBetween(
            _initialPosition!.latitude,
            _initialPosition!.longitude,
            position.latitude,
            position.longitude,
          ) / 1000; // Convert to kilometers
          
          setState(() {
            _currentPosition = position;
            _distance = newDistance;
          });
        }
      });
      
      setState(() {
        _routeStarted = true;
        _routeStartTime = DateTime.now();
        _isTimerRunning = true;
        _elapsedTime = Duration.zero;
        _maxInclination = 0.0;
        _distance = 0.0;
      });
      
      _startTimer();
      _sendCommand("START_ROUTE");
      
    } catch (e) {
      print("Error getting location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error getting location: $e")),
      );
    }
  }

  Future<void> _endRoute() async {
    if (!_routeStarted) return;
    
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    
    setState(() {
      _isTimerRunning = false;
    });
    
    try {
      await _saveRouteData();
      await _sendCommand("END_ROUTE");
      
      setState(() {
        _routeStarted = false;
        _initialPosition = null;
        _currentPosition = null;
      });
      
    } catch (e) {
      print("Error ending route: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao finalizar rota: $e")),
      );
      setState(() {
        _isTimerRunning = true;
      });
    }
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_isTimerRunning) {
        setState(() {
          _elapsedTime = DateTime.now().difference(_routeStartTime);
        });
        _startTimer();
      }
    });
  }

  void _stopTimer() {
    setState(() {
      _isTimerRunning = false;
    });
  }

  Future<void> _sendCommand(String command) async {
    if (_isConnected && _connection != null && _connection!.isConnected) {
      try {
        _connection!.output.add(Uint8List.fromList("$command\n".codeUnits));
        await _connection!.output.allSent;
        print("Command sent: $command");
      } catch (e) {
        print("Error sending command: $e");
        setState(() {
          _isConnected = false;
        });
      }
    }
  }

  Future<void> _saveRouteData() async {
    if (_currentUserId == null || _currentUserNumberId == null) {
      print("User data not available - cannot save route");
      throw Exception("User data not available");
    }

    try {
      final distance = _distance.toStringAsFixed(2);
      final inclination = _medInclination;
      final duration = _elapsedTime.inMinutes;

      print("Attempting to save route data:");
      print("- Distance: $distance km");
      print("- Inclination: $inclination°");
      print("- Duration: $duration minutes");
      print("- User ID: $_currentUserId");
      print("- Friend ID: $_selectedFriendId");

      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId);
      
      final userDoc = await userDocRef.get();
      
      if (!userDoc.exists) {
        throw Exception("User document does not exist");
      }

      List<dynamic> histDistancia = userDoc.data()?['Hist_Distancia']?.toList() ?? [];
      List<dynamic> histNivel = userDoc.data()?['Hist_Nivel']?.toList() ?? [];
      List<dynamic> histTempo = userDoc.data()?['Hist_Tempo']?.toList() ?? [];
      List<dynamic> histAmigos = userDoc.data()?['Hist_Amigos']?.toList() ?? [];

      histDistancia.add(distance);
      histNivel.add(inclination);
      histTempo.add(duration.toString());
      histAmigos.add(_selectedFriendId ?? '');

      await userDocRef.update({
        'Hist_Distancia': histDistancia,
        'Hist_Nivel': histNivel,
        'Hist_Tempo': histTempo,
        'Hist_Amigos': histAmigos,
      });

      if (_selectedFriendId != null && _selectedFriendId!.isNotEmpty) {
        final friendDocRef = FirebaseFirestore.instance
            .collection('users')
            .doc(_selectedFriendId);
        
        final friendDoc = await friendDocRef.get();
        
        if (friendDoc.exists) {
          List<dynamic> friendHistDistancia = friendDoc.data()?['Hist_Distancia']?.toList() ?? [];
          List<dynamic> friendHistNivel = friendDoc.data()?['Hist_Nivel']?.toList() ?? [];
          List<dynamic> friendHistTempo = friendDoc.data()?['Hist_Tempo']?.toList() ?? [];
          List<dynamic> friendHistAmigos = friendDoc.data()?['Hist_Amigos']?.toList() ?? [];

          friendHistDistancia.add(distance);
          friendHistNivel.add(inclination);
          friendHistTempo.add(duration.toString());
          friendHistAmigos.add(_currentUserId!);

          await friendDocRef.update({
            'Hist_Distancia': friendHistDistancia,
            'Hist_Nivel': friendHistNivel,
            'Hist_Tempo': friendHistTempo,
            'Hist_Amigos': friendHistAmigos,
          });
        }
      }

      print("Route data successfully saved to Firestore");
      
    } catch (e) {
      print("Error saving route data: $e");
      rethrow;
    }
  }

  String _formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildActionButton(String text, Color color, bool enabled, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo Percurso'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(
              _isConnected 
                ? Icons.bluetooth_connected 
                : _isScanning 
                  ? Icons.bluetooth_searching 
                  : Icons.bluetooth,
              color: _isConnected ? Colors.blue : Colors.grey,
            ),
            onPressed: _isConnected ? _disconnect : _scanAndConnect,
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/sc2.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.5),
              BlendMode.dstATop,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_isScanning && _devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text("Scanning for devices..."),
                  ),
                if (_isScanning && _devices.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: _devices.map((device) => ListTile(
                        title: Text(device.name ?? "Unknown device"),
                        subtitle: Text(device.address),
                        onTap: () async {
                          try {
                            _device = device;
                            _connection = await BluetoothConnection.toAddress(_device!.address);
                            setState(() {
                              _isConnected = true;
                              _isScanning = false;
                            });
                            
                            // Envia o ID do usuário assim que a conexão é estabelecida
                            if (_currentUserNumberId != null) {
                              await _sendCommand("NOVOID:${_currentUserNumberId}");
                            }

                            _connection!.input!.listen(_handleIncomingData).onDone(() {
                              setState(() {
                                _isConnected = false;
                                _routeStarted = false;
                                _stopTimer();
                              });
                            });
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Failed to connect: $e")),
                            );
                            setState(() {
                              _isScanning = false;
                            });
                          }
                        },
                      )).toList(),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height * 0.6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.blue[800],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.route,
                                  size: 35,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 15),
                              const Text(
                                'Nova Rota',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Tempo Decorrido',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _formatTime(_elapsedTime),
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Inclinação Atual',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${_currentInclination.toStringAsFixed(1)}°',
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Column(
                                      children: [
                                        const Text(
                                          'Inclinação Máxima',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        Text(
                                          '${_maxInclination.toStringAsFixed(1)}°',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      children: [
                                        const Text(
                                          'Inclinação Média',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        Text(
                                          '${_medInclination.toStringAsFixed(1)}°',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          if (_isLoadingFriends)
                            const CircularProgressIndicator()
                          else if (_friendsList.isNotEmpty)
                            Column(
                              children: [
                                const Text(
                                  'Companhia:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue),
                                  ),
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: _selectedFriendId,
                                    hint: const Text('Selecione um amigo'),
                                    underline: Container(),
                                    items: _friendsList.map((friend) {
                                      return DropdownMenuItem<String>(
                                        value: friend['id'],
                                        child: Text(friend['name']),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      setState(() {
                                        _selectedFriendId = newValue;
                                        _selectedFriendName = _friendsList
                                            .firstWhere((friend) => friend['id'] == newValue)['name'];
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 30),
                          
                          Column(
                            children: [
                              _buildActionButton(
                                'Iniciar Rota',
                                Colors.green,
                                _isConnected && !_routeStarted,
                                _startRoute,
                              ),
                              const SizedBox(height: 15),
                              _buildActionButton(
                                'Terminar Rota',
                                Colors.red,
                                _routeStarted,
                                _endRoute,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _disconnect() async {
    if (_routeStarted) {
      await _endRoute();
    }
    await _connection?.close();
    setState(() {
      _isConnected = false;
      _device = null;
    });
  }
}