import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';

void main() {
  runApp(OBDApp());
}

class OBDApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aplicación OBD2 Bluetooth',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Inter',
      ),
      home: OBDHomeScreen(),
    );
  }
}

class OBDHomeScreen extends StatefulWidget {
  @override
  _OBDHomeScreenState createState() => _OBDHomeScreenState();
}

class _OBDHomeScreenState extends State<OBDHomeScreen> {
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _device;
  BluetoothConnection? _connection;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isDiscovering = false;
  String _messageBuffer = '';

  final List<String> _obdCommands = [
    '010C', // Engine RPM
    '010D', // Vehicle Speed
    '010F', // Intake Air Temperature
    '0110', // Mass Air Flow Rate
    '0105', // Engine Coolant Temperature
  ];

  double _rpm = 0.0;
  double _speed = 0.0;
  double _intakeAirTemp = 0.0;
  double _maf = 0.0;
  double _coolantTemp = 0.0;
  Timer? _commandTimer;

  @override
  void dispose() {
    _disconnect();
    _commandTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
  }

  Future<void> _checkBluetoothState() async {
    bool? isEnabled = await _bluetooth.isEnabled;
    if (isEnabled == true) {
      _getPairedDevices();
    } else {
      _requestEnableBluetooth();
    }
  }

  Future<void> _requestEnableBluetooth() async {
    bool? enabled = await _bluetooth.requestEnable();
    if (enabled == true) {
      _getPairedDevices();
    }
  }

  Future<void> _getPairedDevices() async {
    setState(() {
      _isDiscovering = true;
    });

    try {
      List<BluetoothDevice> devices = await _bluetooth.getBondedDevices();
      setState(() {
        _devicesList = devices;
        _isDiscovering = false;
      });
    } catch (error) {
      setState(() {
        _isDiscovering = false;
      });
      _showErrorDialog("Error al buscar dispositivos: $error");
    }
  }

  Future<void> _startDiscovery() async {
    setState(() {
      _isDiscovering = true;
      _devicesList = [];
    });

    _bluetooth.startDiscovery().listen((discoveryResult) {
      if (!_devicesList.any(
        (device) => device.address == discoveryResult.device.address,
      )) {
        setState(() {
          _devicesList.add(discoveryResult.device);
        });
      }
    });

    await Future.delayed(Duration(seconds: 10));
    setState(() {
      _isDiscovering = false;
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
    });

    try {
      _connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        _device = device;
        _isConnected = true;
        _isConnecting = false;
      });

      _startDataListening();
      _startAutoUpdate();
    } catch (error) {
      setState(() {
        _isConnecting = false;
      });
      _showErrorDialog("Error al conectar: ${error.toString()}");
    }
  }

  void _disconnect() {
    _commandTimer?.cancel();
    if (_connection != null) {
      _connection!.close();
      _connection = null;
    }
    setState(() {
      _isConnected = false;
      _device = null;
      _messageBuffer = '';
      _rpm = 0.0;
      _speed = 0.0;
      _intakeAirTemp = 0.0;
      _maf = 0.0;
      _coolantTemp = 0.0;
    });
  }

  void _startDataListening() {
    _connection?.input?.listen(
      (Uint8List data) {
        String newData = String.fromCharCodes(data);
        _messageBuffer += newData;

        while (_messageBuffer.contains('>')) {
          int endIndex = _messageBuffer.indexOf('>');
          if (endIndex > 0) {
            String message = _messageBuffer.substring(0, endIndex).trim();
            _processMessage(message);
            _messageBuffer = _messageBuffer.substring(endIndex + 1);
          } else {
            _messageBuffer = '';
          }
        }
      },
      onDone: () {
        _disconnect();
      },
    );
  }

  void _processMessage(String message) {
    message = message.replaceAll(RegExp(r'[\r\n\s]'), '');

    if (message.isEmpty) return;

    try {
      if (message.startsWith('410C')) {
        int rpmValue = int.parse(message.substring(4, 8), radix: 16);
        setState(() => _rpm = rpmValue / 4);
      } else if (message.startsWith('410D')) {
        int speedValue = int.parse(message.substring(4, 6), radix: 16);
        setState(() => _speed = speedValue.toDouble());
      } else if (message.startsWith('410F')) {
        int tempValue = int.parse(message.substring(4, 6), radix: 16) - 40;
        setState(() => _intakeAirTemp = tempValue.toDouble());
      } else if (message.startsWith('4110')) {
        int mafValue = int.parse(message.substring(4, 8), radix: 16);
        setState(() => _maf = mafValue / 100);
      } else if (message.startsWith('4105')) {
        int tempValue = int.parse(message.substring(4, 6), radix: 16) - 40;
        setState(() => _coolantTemp = tempValue.toDouble());
      }
    } catch (e) {
      print("Error parsing message: $e");
    }
  }

  void _sendCommand(String command) {
    if (_isConnected && _connection != null) {
      command = command + "\r";
      _connection!.output.add(Uint8List.fromList(utf8.encode(command)));
    }
  }

  void _startAutoUpdate() {
    _commandTimer?.cancel();
    _commandTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (_isConnected && _connection != null) {
        for (String command in _obdCommands) {
          _sendCommand(command);
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _showDeviceList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Dispositivos Bluetooth',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Expanded(
                child:
                    _isDiscovering
                        ? Center(child: CircularProgressIndicator())
                        : _devicesList.isEmpty
                        ? Center(child: Text('No se encontraron dispositivos'))
                        : ListView.builder(
                          itemCount: _devicesList.length,
                          itemBuilder: (context, index) {
                            final device = _devicesList[index];
                            return ListTile(
                              leading: Icon(Icons.bluetooth),
                              title: Text(
                                device.name ?? 'Dispositivo desconocido',
                              ),
                              subtitle: Text(device.address),
                              onTap: () {
                                Navigator.pop(context);
                                _connectToDevice(device);
                              },
                            );
                          },
                        ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _getPairedDevices,
                    child: Text('Actualizar dispositivos'),
                  ),
                  ElevatedButton(
                    onPressed: _startDiscovery,
                    child: Text('Buscar nuevos'),
                  ),
                ],
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
      appBar: AppBar(
        title: const Text('OBD2 Bluetooth - Tiempo Real'),
        backgroundColor: _isConnected ? Colors.green : Colors.red,
        actions: [
          IconButton(
            icon: Icon(Icons.bluetooth),
            onPressed: () => _showDeviceList(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: [
                Icon(
                  _isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                SizedBox(width: 8),
                Text(
                  _isConnected
                      ? 'Conectado a: ${_device?.name ?? _device?.address ?? 'Dispositivo OBD2'}'
                      : 'Selecciona un dispositivo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),

            SizedBox(height: 20),

            if (_isConnecting) LinearProgressIndicator(),

            Expanded(
              child:
                  _isConnected
                      ? ListView(
                        children: [
                          _buildDataCard(
                            'RPM del Motor',
                            '${_rpm.toStringAsFixed(0)} RPM',
                            Icons.speed,
                          ),
                          _buildDataCard(
                            'Velocidad',
                            '${_speed.toStringAsFixed(0)} km/h',
                            Icons.directions_car,
                          ),
                          _buildDataCard(
                            'Temp. Aire Admisión',
                            '${_intakeAirTemp.toStringAsFixed(1)} °C',
                            Icons.air,
                          ),
                          _buildDataCard(
                            'Flujo de Aire (MAF)',
                            '${_maf.toStringAsFixed(2)} g/s',
                            Icons.waves,
                          ),
                          _buildDataCard(
                            'Temp. Refrigerante',
                            '${_coolantTemp.toStringAsFixed(1)} °C',
                            Icons.thermostat,
                          ),
                        ],
                      )
                      : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bluetooth_searching,
                              size: 50,
                              color: Colors.blue,
                            ),
                            SizedBox(height: 20),
                            Text(
                              'No conectado',
                              style: TextStyle(fontSize: 20),
                            ),
                            SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () => _showDeviceList(context),
                              child: Text('Seleccionar dispositivo'),
                            ),
                          ],
                        ),
                      ),
            ),

            if (_isConnected)
              Center(
                child: ElevatedButton(
                  onPressed: _disconnect,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text('Desconectar'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataCard(String title, String value, IconData icon) {
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 40, color: Colors.blue),
            SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 16, color: Colors.grey)),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
