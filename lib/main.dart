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
  // Inicialización de Bluetooth
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  // Lista de dispositivos Bluetooth encontrados
  List<BluetoothDevice> _devicesList = [];
  // Dispositivo Bluetooth conectado
  BluetoothDevice? _device;
  // Conexión Bluetooth establecida
  BluetoothConnection? _connection;
  // Estado de la conexión
  bool _isConnecting = false;
  bool _isConnected = false;
  // Mensajes recibidos desde el dispositivo OBD2
  String _messageBuffer = '';
  // Controlador de Text para la entrada de comandos (no se usa en esta versión)
  final TextEditingController _commandController = TextEditingController();
  // Stream para recibir datos del dispositivo
  StreamSubscription<Uint8List>? _streamSubscription;

  // Lista de comandos OBD2 a enviar de forma continua
  final List<String> _obdCommands = [
    '010C', // Engine RPM
    '010D', // Vehicle Speed
    '010F', // Intake Air Temperature
    '0110', // Mass Air Flow Rate
    '0105', // Engine Coolant Temperature
  ];

  // Variables para almacenar datos específicos
  double _rpm = 0.0;
  double _speed = 0.0;
  double _intakeAirTemp = 0.0;
  double _maf = 0.0;
  double _coolantTemp = 0.0;
  Timer? _timer; // Timer para el envío de comandos

  @override
  void dispose() {
    // Limpieza de recursos
    _disconnect();
    _commandController.dispose();
    _timer?.cancel(); // Cancelar el timer si existe
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Habilitar Bluetooth al inicio
    _enableBluetooth();
  }

  // Método para habilitar el Bluetooth
  Future<void> _enableBluetooth() async {
    try {
      // Solicitar habilitar el Bluetooth
      bool? isEnabled = await _bluetooth.requestEnable();
      if (isEnabled == true) {
        // Obtener la lista de dispositivos emparejados
        _getPairedDevices();
      }
    } catch (error) {
      _showErrorDialog("Error al habilitar Bluetooth: $error");
    }
  }

  // Método para mostrar un diálogo de error
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

  // Método para obtener los dispositivos emparejados
  Future<void> _getPairedDevices() async {
    try {
      // Obtener la lista de dispositivos emparejados
      List<BluetoothDevice> devices = await _bluetooth.getBondedDevices();
      setState(() {
        _devicesList = devices;
      });
    } catch (error) {
      _showErrorDialog("Error al obtener dispositivos emparejados: $error");
    }
  }

  // Método para conectar a un dispositivo
  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
    });
    try {
      // Conectar al dispositivo
      _connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        _device = device;
        _isConnected = true;
        _isConnecting = false;
      });
      // Iniciar la escucha de datos
      _startDataListening();
      // Iniciar el envío de comandos automáticamente
      _startAutoUpdate();
    } catch (error) {
      setState(() {
        _isConnecting = false;
      });
      _showErrorDialog("Error al conectar al dispositivo: $error");
    }
  }

  // Método para desconectar del dispositivo
  void _disconnect() {
    if (_connection != null) {
      _connection!.close();
      _connection = null;
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
      if (_streamSubscription != null) {
        _streamSubscription!.cancel();
      }
      _timer?.cancel(); // Cancelar el timer al desconectar
    }
  }

  // Método para iniciar la escucha de datos
  void _startDataListening() {
    _streamSubscription = _connection!.input!.listen((Uint8List data) {
      // Convertir los datos recibidos a una cadena
      String newData = String.fromCharCodes(data);
      _messageBuffer += newData;

      // Procesar el búfer para extraer mensajes completos
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
    });
  }

  // Método para procesar los mensajes recibidos
  void _processMessage(String message) {
    // Aquí se procesan los mensajes recibidos del OBD2.
    // Se eliminan caracteres extraños y se formatea la respuesta.
    message = message.replaceAll(
      RegExp(r'[\r\n\s]'),
      '',
    ); // Remove extra characters
    if (message.isNotEmpty) {
      //TODO: Parse the message for useful information.
      // For example:
      if (message.startsWith('410C')) {
        try {
          int rpmValue = int.parse(message.substring(4, 8), radix: 16);
          setState(() {
            _rpm = rpmValue / 4;
          });
        } catch (e) {
          print("Error parsing RPM: $e");
          _rpm = 0.0;
        }
      } else if (message.startsWith('410D')) {
        try {
          int speedValue = int.parse(message.substring(4, 6), radix: 16);
          setState(() {
            _speed = speedValue.toDouble();
          });
        } catch (e) {
          print("Error parsing Speed: $e");
          _speed = 0.0;
        }
      } else if (message.startsWith('410F')) {
        try {
          int tempValue = int.parse(message.substring(4, 6), radix: 16) - 40;
          setState(() {
            _intakeAirTemp = tempValue.toDouble();
          });
        } catch (e) {
          print("Error parsing Intake Air Temperature: $e");
          _intakeAirTemp = 0.0;
        }
      } else if (message.startsWith('4110')) {
        try {
          int mafValue = int.parse(message.substring(4, 8), radix: 16);
          setState(() {
            _maf = mafValue / 100;
          });
        } catch (e) {
          print("Error parsing MAF: $e");
          _maf = 0.0;
        }
      } else if (message.startsWith('4105')) {
        try {
          int tempValue = int.parse(message.substring(4, 6), radix: 16) - 40;
          setState(() {
            _coolantTemp = tempValue.toDouble();
          });
        } catch (e) {
          print("Error parsing Coolant Temperature: $e");
          _coolantTemp = 0.0;
        }
      } else {
        print("Message: $message");
      }
    }
  }

  // Método para enviar comandos al dispositivo OBD2
  void _sendCommand(String command) {
    if (_isConnected && _connection != null) {
      // Añadir el carácter de fin de línea para que el dispositivo OBD2 lo reconozca
      command = command + "\r";
      List<int> bytes = utf8.encode(command);
      _connection!.output.add(Uint8List.fromList(bytes));
      // Esperar a que los datos se envíen
      _connection!.output.allSent.then((_) {
        // No limpiar el campo de entrada de texto aquí, ya que no se usa para el envío automático.
      });
    } else {
      _showErrorDialog('No se ha conectado a ningún dispositivo.');
    }
  }

  // Método para iniciar el envío automático de comandos OBD2
  void _startAutoUpdate() {
    // Enviar comandos cada 2 segundos (ajusta según sea necesario)
    _timer = Timer.periodic(const Duration(seconds: 2), (Timer timer) {
      if (_isConnected && _connection != null) {
        for (String command in _obdCommands) {
          _sendCommand(command);
        }
      } else {
        timer.cancel(); // Detener el timer si no hay conexión
      }
    });
  }

  // Método para construir la lista de dispositivos
  Widget _buildDeviceList() {
    return ListView.builder(
      itemCount: _devicesList.length,
      itemBuilder: (context, index) {
        final device = _devicesList[index];
        return ListTile(
          title: Text(device.name ?? 'Dispositivo Desconocido'),
          subtitle: Text(device.address),
          onTap: () {
            if (_isConnecting) return;
            _connectToDevice(device);
            Navigator.of(
              context,
            ).pop(); // Cerrar el diálogo después de seleccionar
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OBD2 Bluetooth'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_searching),
            onPressed: () {
              // Mostrar un diálogo para seleccionar el dispositivo
              showDialog(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: const Text('Dispositivos Bluetooth'),
                      content: SizedBox(
                        width: double.maxFinite,
                        height: 300,
                        child: _buildDeviceList(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ],
                    ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _isConnected
                  ? 'Conectado a: ${_device?.name ?? _device?.address ?? 'Desconocido'}'
                  : 'No Conectado',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 10),
            if (_isConnecting) const CircularProgressIndicator(),
            const SizedBox(height: 10),
            // Display the processed data
            Text(
              'RPM: ${_rpm.toStringAsFixed(0)} RPM',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'Speed: ${_speed.toStringAsFixed(0)} km/h',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'Intake Air Temperature: ${_intakeAirTemp.toStringAsFixed(2)} °C',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'MAF: ${_maf.toStringAsFixed(2)} g/s',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'Coolant Temperature: ${_coolantTemp.toStringAsFixed(2)} °C',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 10),
            Expanded(
              child:
              // Muestra los mensajes recibidos.
              Text(_messageBuffer),
            ),
            const SizedBox(height: 10),
            // Dropdown for selecting predefined commands (NO LONGER NEEDED FOR AUTO-UPDATE, BUT KEPT FOR DEBUGGING)
            DropdownButtonFormField<String>(
              value: _obdCommands.first,
              onChanged: (String? newValue) {
                if (newValue != null) {
                  _sendCommand(newValue);
                }
              },
              items:
                  _obdCommands.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
              decoration: const InputDecoration(
                labelText: 'Comandos OBD2 Predefinidos',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    decoration: const InputDecoration(
                      labelText: 'Enviar Comando OBD2',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) {
                      _sendCommand(value);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    _sendCommand(_commandController.text);
                  },
                  child: const Text('Enviar'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: _isConnected ? _disconnect : null,
                child: Text(_isConnected ? 'Desconectar' : 'Desconectar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
