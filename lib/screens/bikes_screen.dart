import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';

class BikesScreen extends StatefulWidget {
  const BikesScreen({super.key});

  @override
  State<BikesScreen> createState() => _BikesScreenState();
}

class _BikesScreenState extends State<BikesScreen> {
  int _intensity = 0; // Valor inicial (0-4)
  bool _isConnected = false;
  bool _isScanning = false;
  BluetoothConnection? _connection;
  BluetoothDevice? _device;
  List<BluetoothDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
  }

  @override
  void dispose() {
    _connection?.dispose();
    super.dispose();
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

        _connection!.input!.listen(_handleIncomingData).onDone(() {
          setState(() {
            _isConnected = false;
          });
        });
      } else {
        setState(() {
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No ESP32 device found")),
        );
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connection failed: $e")),
      );
    }
  }

  void _handleIncomingData(Uint8List data) {
    String incoming = String.fromCharCodes(data);
    print("Received: $incoming");
    
    if (incoming.startsWith("INTENSITY:")) {
      try {
        int newIntensity = int.parse(incoming.substring(10).trim());
        setState(() {
          _intensity = newIntensity.clamp(0, 4); // Ajustado para 0-4
        });
      } catch (e) {
        print("Error parsing intensity: $e");
      }
    }
  }

  Future<void> _sendIntensity(int newIntensity) async {
    newIntensity = newIntensity.clamp(0, 4); // Ajustado para 0-4
    
    if (_isConnected && _connection != null && _connection!.isConnected) {
      try {
        _connection!.output.add(Uint8List.fromList("INTENSITY:$newIntensity\n".codeUnits));
        await _connection!.output.allSent;
        
        setState(() {
          _intensity = newIntensity;
        });
        print("Intensidade alterada para: $newIntensity");
      } catch (e) {
        print("Error sending intensity: $e");
        setState(() {
          _isConnected = false;
        });
      }
    } else {
      print("Not connected to device");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not connected to device")),
      );
    }
  }

  Future<void> _disconnect() async {
    await _connection?.close();
    setState(() {
      _isConnected = false;
      _device = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bicicletas'),
        elevation: 0,
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
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
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
                            _connection!.input!.listen(_handleIncomingData).onDone(() {
                              setState(() {
                                _isConnected = false;
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
                                  Icons.pedal_bike,
                                  size: 35,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 15),
                              const Text(
                                'Controle de Bicicleta',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Frequência do Sinalizador',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '$_intensity',
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(4, (index) { // Alterado para 4 níveis
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                        child: Container(
                                          width: 30,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: index < _intensity 
                                                ? Colors.blue[800]
                                                : Colors.grey[300],
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildControlButton(
                                icon: Icons.remove,
                                onPressed: () => _sendIntensity(_intensity - 1),
                                isActive: _intensity > 0,
                              ),
                              _buildControlButton(
                                icon: Icons.add,
                                onPressed: () => _sendIntensity(_intensity + 1),
                                isActive: _intensity < 4, // Alterado para 4
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildNavButton(
                                icon: Icons.arrow_back,
                                onPressed: () => _sendCommand("SETAESQUERDA"),
                              ),
                              _buildNavButton(
                                icon: Icons.arrow_forward,
                                onPressed: () => _sendCommand("SETADIREITA"),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao enviar comando: $e")),
      );
    }
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Não conectado ao dispositivo")),
    );
  }
}

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isActive,
  }) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: isActive ? Colors.blue[800] : Colors.grey[400],
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (isActive ? Colors.blue : Colors.grey).withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 30, color: Colors.white),
        onPressed: isActive ? onPressed : null,
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 30, color: Colors.blue[800]),
        onPressed: onPressed,
      ),
    );
  }
}