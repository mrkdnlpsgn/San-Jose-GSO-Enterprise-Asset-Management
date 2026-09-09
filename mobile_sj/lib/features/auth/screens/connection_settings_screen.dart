import 'package:flutter/material.dart';
import '../../../shared/widgets/server_address_card.dart';

// Reachable from the login screen, before authentication — if the saved
// server address is wrong (new network, different Wi-Fi than the backend),
// login fails before the user can ever reach the authenticated Settings
// screen to fix it. This is the same ServerAddressCard shown there, just
// exposed pre-login too so that dead end doesn't exist.
class ConnectionSettingsScreen extends StatelessWidget {
  const ConnectionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connection Settings')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: const ServerAddressCard(),
            ),
          ),
        ),
      ),
    );
  }
}
