import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';

class MotorSensorScreen extends StatefulWidget {
  @override
  _MotorSensorScreenState createState() => _MotorSensorScreenState();
}

class _MotorSensorScreenState extends State<MotorSensorScreen> {
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _device;
  BluetoothConnection? _connection;
  bool _isConnecting = false;
  bool _isConnected = false;
  String _messageBuffer = '';
  String _vin = 'No disponible';
  bool _isFetchingVin = false;
  List<String> _vinCommands = ['0902', '22 194', '21 194'];
  int _currentVinCommandIndex = 0;

  // Variables para los datos OBD2
  double _coolantTemp = 0.0;
  double _rpm = 0.0;
  double _engineLoad = 0.0;
  double _ignitionAdvance = 0.0;
  double _speed = 0.0;
  double _maf = 0.0;
  double _intakeManifoldPressure = 0.0;

  Timer? _commandTimer;
  int _currentCommandIndex = 0;

  final List<String> _obdCommands = [
    '0105', // Temperatura refrigerante
    '010C', // RPM motor
    '0104', // Carga del motor
    '010E', // Avance de encendido
    '010D', // Velocidad del vehículo
    '0110', // Flujo de aire masivo (MAF)
    '010B', // Presión del colector de admisión
  ];

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
    try {
      List<BluetoothDevice> devices = await _bluetooth.getBondedDevices();
      setState(() {
        _devicesList = devices;
      });

      if (devices.isNotEmpty) {
        _connectToDevice(
          devices.firstWhere(
            (d) => d.name?.toLowerCase().contains("obd") ?? false,
            orElse: () => devices.first,
          ),
        );
      }
    } catch (error) {
      _showError("Error al buscar dispositivos: $error");
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() => _isConnecting = true);

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
      setState(() => _isConnecting = false);
      _showError("Error al conectar: ${error.toString()}");
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
      // Resetear valores
      _coolantTemp = 0.0;
      _rpm = 0.0;
      _engineLoad = 0.0;
      _ignitionAdvance = 0.0;
      _speed = 0.0;
      _maf = 0.0;
      _intakeManifoldPressure = 0.0;
      _vin = 'No disponible';
      _isFetchingVin = false;
    });
  }

  void _startDataListening() {
    _connection?.input?.listen((Uint8List data) {
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
    }, onDone: _disconnect);
  }

  void _processMessage(String message) {
    message = message.replaceAll(RegExp(r'[\r\n\s]'), '').toUpperCase();

    if (message.startsWith('4105') && message.length >= 6) {
      try {
        int tempValue = int.parse(message.substring(4, 6), radix: 16) - 40;
        setState(() => _coolantTemp = tempValue.toDouble());
      } catch (e) {
        print("Error procesando temperatura: $e");
      }
    } else if (message.startsWith('410C') && message.length >= 8) {
      try {
        int rpmValue = int.parse(message.substring(4, 8), radix: 16);
        setState(() => _rpm = rpmValue / 4.0);
      } catch (e) {
        print("Error procesando RPM: $e");
      }
    } else if (message.startsWith('4104') && message.length >= 6) {
      try {
        int loadValue = int.parse(message.substring(4, 6), radix: 16);
        setState(() => _engineLoad = (loadValue * 100 / 255).toDouble());
      } catch (e) {
        print("Error procesando carga del motor: $e");
      }
    } else if (message.startsWith('410E') && message.length >= 6) {
      try {
        int advanceValue = int.parse(message.substring(4, 6), radix: 16) - 64;
        setState(() => _ignitionAdvance = advanceValue.toDouble());
      } catch (e) {
        print("Error procesando avance de encendido: $e");
      }
    } else if (message.startsWith('410D') && message.length >= 6) {
      try {
        int speedValue = int.parse(message.substring(4, 6), radix: 16);
        setState(() => _speed = speedValue.toDouble());
      } catch (e) {
        print("Error procesando velocidad: $e");
      }
    } else if (message.startsWith('4110') && message.length >= 8) {
      try {
        int mafValue = int.parse(message.substring(4, 8), radix: 16);
        setState(() => _maf = mafValue / 100.0);
      } catch (e) {
        print("Error procesando MAF: $e");
      }
    } else if (message.startsWith('410B') && message.length >= 6) {
      try {
        int pressureValue = int.parse(message.substring(4, 6), radix: 16);
        setState(() => _intakeManifoldPressure = pressureValue.toDouble());
      } catch (e) {
        print("Error procesando presión del colector: $e");
      }
    } else if (message.contains('490201') ||
        message.contains('62194') ||
        message.contains('61194')) {
      try {
        String vinHex = message.replaceAll(RegExp(r'[^0-9A-F]'), '');
        String vin = '';

        if (message.contains('490201')) {
          vinHex = vinHex.substring(vinHex.indexOf('490201') + 6);
        } else if (message.contains('62194')) {
          vinHex = vinHex.substring(vinHex.indexOf('62194') + 5);
        } else if (message.contains('61194')) {
          vinHex = vinHex.substring(vinHex.indexOf('61194') + 5);
        }

        for (int i = 0; i < vinHex.length; i += 2) {
          if (i + 2 > vinHex.length) break;
          String hexPair = vinHex.substring(i, i + 2);
          try {
            int charCode = int.parse(hexPair, radix: 16);
            if (charCode >= 32 && charCode <= 126) {
              vin += String.fromCharCode(charCode);
            }
          } catch (e) {
            print("Error convirtiendo caracter VIN: $e");
          }
        }

        vin = vin.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').trim();

        if (vin.length >= 17) {
          vin = vin.substring(0, 17);
          setState(() => _vin = vin);
        } else if (vin.isNotEmpty) {
          setState(() => _vin = vin);
        }
      } catch (e) {
        print("Error procesando VIN: $e");
      }
    }
  }

  void _sendCommand(String command) {
    if (_isConnected && _connection != null) {
      command = '$command\r';
      _connection!.output.add(Uint8List.fromList(utf8.encode(command)));
    }
  }

  void _startAutoUpdate() {
    _commandTimer?.cancel();
    _commandTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (_isConnected && _connection != null) {
        _sendCommand(_obdCommands[_currentCommandIndex]);
        _currentCommandIndex = (_currentCommandIndex + 1) % _obdCommands.length;
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _getVin() async {
    if (!_isConnected || _connection == null || _isFetchingVin) return;

    setState(() {
      _isFetchingVin = true;
      _vin = 'Buscando VIN...';
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Text('Obteniendo VIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_vin),
                SizedBox(height: 20),
                CircularProgressIndicator(),
              ],
            ),
          ),
    );

    try {
      bool vinFound = false;
      final maxAttempts = _vinCommands.length;
      int attempts = 0;

      while (!vinFound && attempts < maxAttempts) {
        _sendCommand(_vinCommands[_currentVinCommandIndex]);
        await Future.delayed(Duration(seconds: 3));

        if (_vin.length >= 17 &&
            _vin != 'No disponible' &&
            _vin != 'Buscando VIN...') {
          vinFound = true;
        } else {
          _currentVinCommandIndex =
              (_currentVinCommandIndex + 1) % _vinCommands.length;
          attempts++;
        }
      }

      Navigator.of(context).pop();

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text('VIN del Vehículo'),
              content: Text(
                _vin.length >= 17 ? _vin : 'No se pudo obtener el VIN',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cerrar'),
                ),
              ],
            ),
      );
    } catch (e) {
      print("Error obteniendo VIN: $e");
      Navigator.of(context).pop();
      _showError("Error al obtener el VIN");
    } finally {
      setState(() => _isFetchingVin = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showDeviceList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Dispositivos Bluetooth', style: TextStyle(fontSize: 20)),
                Expanded(
                  child:
                      _devicesList.isEmpty
                          ? Center(
                            child: Text('No se encontraron dispositivos'),
                          )
                          : ListView.builder(
                            itemCount: _devicesList.length,
                            itemBuilder:
                                (context, index) => ListTile(
                                  title: Text(
                                    _devicesList[index].name ?? 'Desconocido',
                                  ),
                                  subtitle: Text(_devicesList[index].address),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _connectToDevice(_devicesList[index]);
                                  },
                                ),
                          ),
                ),
                ElevatedButton(
                  onPressed: _getPairedDevices,
                  child: Text('Actualizar lista'),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Monitor de Sensores'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.bluetooth),
            onPressed: () => _showDeviceList(context),
          ),
          if (_isConnected)
            IconButton(
              icon: Icon(Icons.car_repair),
              onPressed: _getVin,
              tooltip: 'Obtener VIN',
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isConnected)
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.all(10),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text('RPM', style: TextStyle(fontSize: 18)),
                                  SizedBox(height: 8),
                                  Text(
                                    '${_rpm.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.all(10),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(
                                    'Velocidad',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '${_speed.toStringAsFixed(0)} km/h',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.all(10),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(
                                    'Temp. °C',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '${_coolantTemp.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.all(10),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(
                                    'Carga %',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '${_engineLoad.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.all(10),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(
                                    'Avance °',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '${_ignitionAdvance.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.all(10),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(
                                    'MAF (g/s)',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '${_maf.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.all(10),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(
                                    'Presión Colector (kPa)',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '${_intakeManifoldPressure.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _disconnect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                      ),
                      child: Text(
                        'DESCONECTAR',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    Icon(
                      Icons.bluetooth_disabled,
                      size: 60,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 20),
                    Text(
                      _isConnecting ? 'Conectando...' : 'No conectado',
                      style: TextStyle(fontSize: 24),
                    ),
                    SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: () => _showDeviceList(context),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                      ),
                      child: Text('CONECTAR', style: TextStyle(fontSize: 18)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
