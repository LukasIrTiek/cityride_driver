import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../driver/driver_home.dart';
import '../location_permission_page.dart';
import 'driver_login.dart';
import 'package:geolocator/geolocator.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<Widget> _getNextScreen(String userId) async {
    // 1. Tikriname paskyros būseną
    final driverData = await Supabase.instance.client
        .from('drivers')
        .select('verification_status')
        .eq('id', userId)
        .maybeSingle();
    
    final status = driverData?['verification_status'];
    if (status == 'deletion_pending') {
      return const DeletionPendingScreen();
    }

    // 2. Tikriname vietovės leidimą
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return const LocationPermissionPage();
    }
    
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationPermissionPage();
    }

    return const DriverHomePage();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return FutureBuilder<Widget>(
            future: _getNextScreen(session.user.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.red)));
              }
              return snapshot.data ?? const DriverLoginPage();
            },
          );
        }

        return const DriverLoginPage();
      },
    );
  }
}

class DeletionPendingScreen extends StatelessWidget {
  const DeletionPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_forever, size: 80, color: Colors.red),
            const SizedBox(height: 24),
            const Text(
              'Paskyros ištrynimas vykdomas',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Jūsų prašymas ištrinti paskyrą yra peržiūrimas. Programėle naudotis nebegalite. Paskyra bus visiškai pašalinta per 24 valandas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                child: const Text('IŠEITI'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}