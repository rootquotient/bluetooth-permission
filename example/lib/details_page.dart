import 'package:flutter/material.dart';

class DetailsPage extends StatelessWidget {
  final Map<String, dynamic> device;
  const DetailsPage({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final String userName = "Alice";
    final int age = 25;
    final String email = "alice@example.com";
    final String deviceName = device['name'] ?? 'Unknown Device';
    final String id = device['id'] ?? '';
    final int rssi = device['rssi'] ?? 0;
    final List<String> serviceUUIDs =
        List<String>.from(device['serviceUUIDs'] ?? []);
    final timestamp = device['timestamp'];
    final DateTime? lastSeen = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round())
        : null;

    return Scaffold(
      appBar: AppBar(title: Text("Profile & Bluetooth Info")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text(
              '👤 Personal Details',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            infoRow("Name", userName),
            infoRow("Age", "$age"),
            infoRow("Email", email),
            SizedBox(height: 24),
            Text(
              '📡 Bluetooth Device Info',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            infoRow("Device Name", deviceName),
            infoRow("Device ID", id),
            infoRow("RSSI", "$rssi dBm"),
            if (lastSeen != null)
              infoRow("Last Seen", lastSeen.toLocal().toString()),
            if (serviceUUIDs.isNotEmpty) ...[
              SizedBox(height: 16),
              Text(
                'Service UUIDs:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              ...serviceUUIDs.map((uuid) => Padding(
                    padding: EdgeInsets.only(left: 8, top: 4),
                    child: Text(
                      uuid,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.blue[700],
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              "$label:",
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontFamily: 'monospace', color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
