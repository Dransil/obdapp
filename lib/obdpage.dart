import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:convert';

class OBDPage extends StatefulWidget {
  @override
  _OBDPageState createState() => _OBDPageState();
}

class _OBDPageState extends State<OBDPage> {
  BluetoothConnection? connection;
  bool isConnecting = false;
  bool isConnected = false;
  String rawResponse = '';
  String rpmValue = '';
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _selectedDevice;

  void scanDevices() async {
    setState(() {
      isConnecting = false;
      rawResponse = '';
      rpmValue = '';
      _selectedDevice = null;
      _devicesList = [];
    });

    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        _devicesList = devices;
      });
    } catch (e) {
      print("Error escaneando dispositivos: $e");
    }
  }

  Future<void> initializeELM327() async {
    List<String> initCommands = [
      "ATZ\r", // Reset
      "ATE0\r", // Echo off
      "ATL0\r", // Linefeeds off
      "ATS0\r", // Spaces off
      "ATH0\r", // Headers off
      "ATSP0\r", // Auto protocol
    ];

    for (String command in initCommands) {
      print("Enviando: $command");
      connection!.output.add(ascii.encode(command));
      await connection!.output.allSent;
      await Future.delayed(Duration(milliseconds: 300));
    }
  }

  void connectToDevice() async {
    if (_selectedDevice == null) return;

    setState(() {
      isConnecting = true;
    });

    try {
      connection = await BluetoothConnection.toAddress(
        _selectedDevice!.address,
      );
      print("Conectado a ${_selectedDevice!.name}");
      setState(() {
        isConnected = true;
        isConnecting = false;
      });

      connection!.input!
          .listen((data) {
            String response = ascii.decode(data);
            print('Data incoming: $response');

            setState(() {
              rawResponse += response;
            });

            if (rawResponse.contains('41 0C')) {
              extractRPM(rawResponse);
              rawResponse = '';
            }
          })
          .onDone(() {
            print('Conexión terminada');
            setState(() {
              isConnected = false;
            });
          });

      // Inicializar ELM327
      await initializeELM327();
      await Future.delayed(Duration(seconds: 1));

      // Solicitar RPM (PID 010C)
      connection!.output.add(ascii.encode("010C\r"));
      await connection!.output.allSent;
    } catch (e) {
      print("Error conectando: $e");
      setState(() {
        isConnecting = false;
      });
    }
  }

  void extractRPM(String response) {
    try {
      final match = RegExp(
        r'41\s0C\s([0-9A-Fa-f]{2})\s([0-9A-Fa-f]{2})',
      ).firstMatch(response);

      if (match != null) {
        final A = int.parse(match.group(1)!, radix: 16);
        final B = int.parse(match.group(2)!, radix: 16);
        final rpm = ((A * 256) + B) / 4;

        setState(() {
          rpmValue = rpm.toStringAsFixed(0);
        });
      }
    } catch (e) {
      print("Error decodificando RPM: $e");
    }
  }

  @override
  void dispose() {
    connection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("OBD2 Manual Scan")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: scanDevices,
              child: Text("Escanear Dispositivos Emparejados"),
            ),
            SizedBox(height: 10),

            if (_devicesList.isNotEmpty)
              DropdownButton<BluetoothDevice>(
                hint: Text("Selecciona un dispositivo"),
                value: _selectedDevice,
                onChanged: (BluetoothDevice? newDevice) {
                  setState(() {
                    _selectedDevice = newDevice;
                  });
                },
                items:
                    _devicesList.map((device) {
                      return DropdownMenuItem(
                        child: Text(device.name ?? device.address),
                        value: device,
                      );
                    }).toList(),
              ),

            SizedBox(height: 10),

            if (_selectedDevice != null && !isConnected)
              ElevatedButton(
                onPressed: connectToDevice,
                child:
                    isConnecting
                        ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : Text("Conectar"),
              ),

            SizedBox(height: 20),

            if (isConnected)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("✅ Conectado a: ${_selectedDevice?.name}"),
                  SizedBox(height: 10),
                  Text("Respuesta OBD Cruda:"),
                  Text(rawResponse, style: TextStyle(fontSize: 14)),
                  SizedBox(height: 10),
                  if (rpmValue.isNotEmpty)
                    Text(
                      "🔄 RPM Detectado: $rpmValue",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
