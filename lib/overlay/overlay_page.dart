import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class OverlayPage extends StatefulWidget {
  const OverlayPage({super.key});

  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<OverlayPage> {
  Map<String, dynamic>? rideData;
  SupabaseClient? _supabase;
  bool isProcessing = false;
  String? incomingRideEta;

  SupabaseClient get supabase {
    if (_supabase != null) return _supabase!;
    try {
      _supabase = Supabase.instance.client;
    } catch (_) {
      _supabase = SupabaseClient(
        dotenv.env['SUPABASE_URL'] ?? '',
        dotenv.env['SUPABASE_ANON_KEY'] ?? ''
      );
    }
    return _supabase!;
  }

  @override
  void initState() {
    super.initState();
    _initOverlay();
    
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (mounted) {
        setState(() {
          rideData = Map<String, dynamic>.from(data);
        });
        if (rideData?['pickup_address'] != null) {
          _calculateEta(rideData!['pickup_address']);
        }
      }
    });
  }

  Future<void> _initOverlay() async {
    if (!dotenv.isInitialized) {
      try {
        await dotenv.load(fileName: ".env");
      } catch (e) {
        debugPrint('Dotenv load error in overlay: $e');
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _calculateEta(String address) async {
    try {
      final googleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
      if (googleApiKey.isEmpty) return;
      
      final position = await Geolocator.getCurrentPosition();
      final url = 'https://maps.googleapis.com/maps/api/directions/json?origin=${position.latitude},${position.longitude}&destination=${Uri.encodeComponent(address)}&key=$googleApiKey';
      final res = await http.get(Uri.parse(url));
      final data = jsonDecode(res.body);
      
      if (data['routes'].isNotEmpty && mounted) {
        setState(() {
          incomingRideEta = data['routes'][0]['legs'][0]['duration']['text'];
        });
      }
    } catch (_) {}
  }

  Future<void> _acceptRide() async {
    if (rideData == null || isProcessing) return;
    setState(() => isProcessing = true);

    try {
      final driverId = rideData!['driver_id'] ?? supabase.auth.currentUser?.id;
      if (driverId == null) throw Exception('Vairuotojas nerastas');

      await supabase.from('rides').update({
        'status': 'accepted', 
        'driver_id': driverId, 
        'driver_lat': (await Geolocator.getCurrentPosition()).latitude,
        'driver_lng': (await Geolocator.getCurrentPosition()).longitude,
        'accepted_at': DateTime.now().toIso8601String(),
      }).eq('id', rideData!['ride_id']).eq('status', 'searching');

      await FlutterOverlayWindow.closeOverlay();
    } catch (e) {
      debugPrint('Overlay Accept Error: $e');
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _rejectRide() async {
    if (rideData == null || isProcessing) return;
    setState(() => isProcessing = true);

    try {
      final rideId = rideData!['ride_id'];
      final driverId = rideData!['driver_id'] ?? supabase.auth.currentUser?.id;

      if (rideId != null && driverId != null) {
        final res = await supabase.from('rides').select('rejected_by').eq('id', rideId).single();
        List rejectedBy = res['rejected_by'] ?? [];
        if (!rejectedBy.contains(driverId)) {
          rejectedBy.add(driverId);
          await supabase.from('rides').update({
            'rejected_by': rejectedBy, 
            'current_target_driver_id': null
          }).eq('id', rideId);
        }
        
        await supabase.functions.invoke('send-ride-notification', body: {
          'ride_id': rideId,
          'title': '🚕 Naujas užsakymas',
          'message': 'Pasiėmimas: ${rideData!['pickup_address']}',
          'lat': rideData!['pickup_lat'],
          'lng': rideData!['pickup_lng']
        });
      }
      
      await FlutterOverlayWindow.closeOverlay();
    } catch (e) {
      debugPrint('Overlay Reject Error: $e');
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (rideData == null) return const SizedBox();

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 25, spreadRadius: 5)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('NAUJAS UŽSAKYMAS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 11)),
                    Text(rideData!['passenger_name'] ?? 'Keleivis', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22), maxLines: 1),
                  ])),
                  Text('€${(double.tryParse(rideData!['price']?.toString() ?? '0') ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 15),
              if (incomingRideEta != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Text('Atvyksite per $incomingRideEta', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
                ),
              _buildAddressRow(Icons.circle, rideData!['pickup_address'] ?? '...', Colors.green),
              const SizedBox(height: 8),
              _buildAddressRow(Icons.location_on, rideData!['destination_address'] ?? '...', Colors.red),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: SizedBox(height: 55, child: OutlinedButton(onPressed: isProcessing ? null : _rejectRide, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red, width: 2), foregroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))), child: const Text('ATMESTI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))))),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: SizedBox(height: 55, child: ElevatedButton(onPressed: isProcessing ? null : _acceptRide, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, elevation: 3, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))), child: isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Text('PRIIMTI', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18))))),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressRow(IconData icon, String text, Color color) {
    return Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 10), Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)))]);
  }
}
