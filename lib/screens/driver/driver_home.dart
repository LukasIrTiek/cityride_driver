import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cityride_driver/screens/pajamos_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../admin/admin_drivers_page.dart';
import '../auth/driver_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'news_page.dart';
import 'chat_page.dart';

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

  GoogleMapController? mapController;
  List rides = [];
  Map<String, dynamic>? currentRide;
  bool isWorking = false;
  String? fcmToken;

  Timer? _ridesRefreshTimer;
  StreamSubscription<Position>? _positionStream;
  RealtimeChannel? ridesChannel;

  late final String driverId;
  late final String googleApiKey;

  LatLng currentPosition = const LatLng(54.8985, 23.9036);
  bool loadingLocation = true;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  String etaText = '';
  String? incomingRideEta;
  bool hadActiveRide = false;
  bool _isFetching = false;
  bool _isFollowingDriver = true;
  
  final Set<String> _rejectedRideIds = {};

  String mapStyle = '''
[
  { "featureType": "poi", "stylers": [ { "visibility": "off" } ] },
  { "featureType": "transit", "stylers": [ { "visibility": "off" } ] },
  { "featureType": "administrative", "elementType": "labels", "stylers": [ { "visibility": "off" } ] },
  { "featureType": "landscape", "stylers": [ { "color": "#f5f5f5" } ] },
  { "featureType": "road", "elementType": "geometry", "stylers": [ { "color": "#ffffff" } ] },
  { "featureType": "road.highway", "elementType": "geometry", "stylers": [ { "color": "#ffe082" } ] },
  { "featureType": "building", "stylers": [ { "visibility": "simplified" }, { "color": "#e0e0e0" } ] }
]
''';

  @override
  void initState() {
    super.initState();
    driverId = supabase.auth.currentUser?.id ?? '';
    googleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    WidgetsBinding.instance.addObserver(this);
    _initializeDriver();
  }

  Future<void> _initializeDriver() async {
    final driver = await supabase.from('drivers').select('online').eq('id', driverId).single();
    if (mounted) setState(() => isWorking = driver['online'] ?? false);
    
    if (isWorking) {
      LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = const AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 3,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        );
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings
      ).listen(_handlePositionUpdate);
    }

    await setupFCM();
    await initializeNotifications();
    await getCurrentLocation();
    await restoreActiveRide();
    await startForegroundService();
    subscribeToRideUpdates();
    
    _ridesRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!isWorking) return;
      if (currentRide == null) {
        await fetchRides();
      } else {
        await restoreActiveRide();
      }
    });
  }

  Future<void> initializeNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(android: androidSettings);
    await notifications.initialize(settings);
    await notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  Future<void> setupFCM() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    fcmToken = await messaging.getToken();
    if (fcmToken != null) {
      await supabase.from('drivers').update({'fcm_token': fcmToken}).eq('id', driverId);
    }
  }

  Future<void> startForegroundService() async {
    FlutterForegroundTask.initCommunicationPort();
    await FlutterForegroundTask.startService(
      notificationTitle: '🟢 CityRide Vairuotojas',
      notificationText: 'Laukiama užsakymų',
    );
  }

  Future<void> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      currentPosition = LatLng(position.latitude, position.longitude);
      _updateMarkers();
      if (mapController != null) mapController!.animateCamera(CameraUpdate.newLatLngZoom(currentPosition, 15));
      setState(() => loadingLocation = false);
    } catch (e) {
      setState(() => loadingLocation = false);
    }
  }

  int _waitingSeconds = 0;
  Timer? _waitingTimer;

  void _updateMarkers() {
    markers.clear();
    if (currentRide != null) {
      final status = currentRide!['status'];
      if (status == 'accepted' || status == 'arrived') {
        markers.add(Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(currentRide!['pickup_lat'] ?? 0, currentRide!['pickup_lng'] ?? 0),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ));
      } else if (status == 'in_progress') {
        markers.add(Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(currentRide!['destination_lat'] ?? 0, currentRide!['destination_lng'] ?? 0),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ));
      }
    }
  }

  void toggleWorking() async {
    final driver = await supabase.from('drivers').select('verification_status').eq('id', driverId).single();
    if (driver['verification_status'] != 'approved') {
      _showNotApprovedDialog();
      return;
    }
    
    setState(() => isWorking = !isWorking);
    
    if (isWorking) {
      // Pirmiausia gauname vietą ir tik tada pažymime online
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      currentPosition = LatLng(pos.latitude, pos.longitude);
      
      await supabase.from('drivers').update({
        'online': true, 
        'lat': pos.latitude, 
        'lng': pos.longitude,
        'last_seen_at': DateTime.now().toIso8601String()
      }).eq('id', driverId);

      LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = const AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 3,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        );
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings
      ).listen(_handlePositionUpdate);
    } else {
      _positionStream?.cancel();
      await supabase.from('drivers').update({'online': false}).eq('id', driverId);
      setState(() { rides = []; currentRide = null; polylines.clear(); });
    }
  }

  void _handlePositionUpdate(Position position) async {
    currentPosition = LatLng(position.latitude, position.longitude);
    await supabase.from('drivers').update({'lat': position.latitude, 'lng': position.longitude, 'last_seen_at': DateTime.now().toIso8601String()}).eq('id', driverId);
    
    if (currentRide != null) { 
      await calculateETA(); 
      await supabase.from('rides').update({'driver_lat': currentPosition.latitude, 'driver_lng': currentPosition.longitude}).eq('id', currentRide!['id']);
    }
    
    if (mapController != null && _isFollowingDriver) {
      mapController!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: currentPosition, 
        zoom: currentRide != null ? 17.5 : 15, 
        tilt: currentRide != null ? 40 : 0, 
        bearing: position.heading
      )));
    }
    if (mounted) setState(() {});
  }

  void subscribeToRideUpdates() {
    ridesChannel = supabase.channel('rides_live').onPostgresChanges(
      event: PostgresChangeEvent.all, schema: 'public', table: 'rides',
      callback: (payload) async { if (isWorking) { await fetchRides(); await restoreActiveRide(); } },
    ).subscribe();
  }

  Future<void> fetchRides() async {
    if (!isWorking || currentRide != null || _isFetching) return;
    _isFetching = true;
    try {
      final response = await supabase.from('rides')
          .select()
          .eq('status', 'searching')
          .eq('current_target_driver_id', driverId);
      
      if (mounted) {
        final newRides = response.where((r) => !_rejectedRideIds.contains(r['id'].toString())).toList();
        
        setState(() {
          if (newRides.isNotEmpty) {
            rides = newRides;
          } else if (rides.isNotEmpty) {
            // Anti-flicker: if new list is empty but we had rides, 
            // wait a few seconds before clearing, just in case it's a temporary poll gap.
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && currentRide == null) {
                _checkAndClearRides();
              }
            });
          }
          _isFetching = false;
        });
        
        if (rides.isNotEmpty) _calculateIncomingEta(rides.first['pickup_address']);
      }
    } catch (e) { 
      _isFetching = false; 
    }
  }

  Future<void> _checkAndClearRides() async {
    if (!isWorking || currentRide != null) return;
    try {
      final response = await supabase.from('rides')
          .select()
          .eq('status', 'searching')
          .eq('current_target_driver_id', driverId);
      if (mounted && response.isEmpty) {
        setState(() { rides = []; });
      }
    } catch (_) {}
  }

  Future<void> _calculateIncomingEta(String address) async {
    try {
      final url = 'https://maps.googleapis.com/maps/api/directions/json?origin=${currentPosition.latitude},${currentPosition.longitude}&destination=${Uri.encodeComponent(address)}&key=$googleApiKey';
      final res = await http.get(Uri.parse(url));
      final data = jsonDecode(res.body);
      if (data['routes'].isNotEmpty && mounted) {
        setState(() { incomingRideEta = data['routes'][0]['legs'][0]['duration']['text']; });
      }
    } catch (_) {}
  }

  Future<void> restoreActiveRide() async {
    final response = await supabase.from('rides').select().eq('driver_id', driverId).neq('status', 'cancelled').inFilter('status', ['accepted', 'arrived', 'in_progress']);
    
    if (response.isEmpty) {
      if (hadActiveRide && currentRide != null && currentRide!['status'] != 'completed') {
        WakelockPlus.disable(); // Išjungiame ekrano budėjimo rėžimą
        _showCancellationDialog(currentRide);
      }
      if (mounted && currentRide != null) {
        setState(() { 
          currentRide = null; 
          etaText = ''; 
          polylines.clear(); 
          hadActiveRide = false; 
        });
      }
      return;
    }
    
    final newRide = response.first;
    if (currentRide == null || currentRide!['status'] != newRide['status']) {
      WakelockPlus.enable(); // Aktyvuojame ekrano budėjimo rėžimą
      setState(() { 
        currentRide = newRide; 
        hadActiveRide = true;
      });
      // Jei accepted - i paemima, jei arrived/in_progress - i tiksla
      final target = (currentRide!['status'] == 'accepted') 
          ? currentRide!['pickup_address'] 
          : currentRide!['destination_address'];

      await drawRoute(currentPosition, target);
      await calculateETA();
    }
  }

  Future<void> calculateETA() async {
    if (currentRide == null) return;
    try {
      final target = currentRide!['status'] == 'in_progress' ? currentRide!['destination_address'] : currentRide!['pickup_address'];
      final url = 'https://maps.googleapis.com/maps/api/directions/json?origin=${currentPosition.latitude},${currentPosition.longitude}&destination=${Uri.encodeComponent(target)}&key=$googleApiKey';
      final res = await http.get(Uri.parse(url));
      final data = jsonDecode(res.body);
      if (data['routes'].isNotEmpty) {
        etaText = data['routes'][0]['legs'][0]['duration']['text'];
        await supabase.from('rides').update({'eta_to_pickup': etaText}).eq('id', currentRide!['id']);
      }
    } catch (_) {}
  }

  Future<void> acceptRide(Map<String, dynamic> ride) async {
    try {
      final driverData = await supabase.from('drivers').select('full_name, car_model, auto_nav').eq('id', driverId).single();
      
      // Update with existing columns in 'rides' table
      final acceptedRide = await supabase.from('rides').update({
        'status': 'accepted', 
        'driver_id': driverId, 
        'driver_lat': currentPosition.latitude, 
        'driver_lng': currentPosition.longitude,
        'accepted_at': DateTime.now().toIso8601String(),
      }).eq('id', ride['id']).eq('status', 'searching').select().single();
      
      setState(() { currentRide = acceptedRide; incomingRideEta = null; _isFollowingDriver = true; });
      await drawRoute(currentPosition, currentRide!['pickup_address']);
      
      WakelockPlus.enable(); // Aktyvuojame ekrano budėjimo rėžimą
      
      // AUTOMATINĖ NAVIGACIJA
      if (driverData['auto_nav'] == true) {
        _openNav();
      }
      
      // NAUJA: Pranešame keleiviui, kad vairuotojas priėmė užsakymą
      try {
        await supabase.functions.invoke('notify-passenger', body: {
          'ride_id': ride['id'],
          'title': '🚕 Vairuotojas pakeliui!',
          'message': '${driverData['full_name']} priėmė jūsų užsakymą ir atvyks su ${driverData['car_model']}.',
        });
      } catch (e) {
        debugPrint('Notify passenger error: $e');
      }
    } catch (e) { debugPrint('ACCEPT ERROR: $e'); }
  }
  
  void rejectRide(Map<String, dynamic> ride) async {
    try {
      final res = await supabase.from('rides').select('rejected_by').eq('id', ride['id']).single();
      List rejectedBy = res['rejected_by'] ?? [];
      if (!rejectedBy.contains(driverId)) {
        rejectedBy.add(driverId);
        await supabase.from('rides').update({'rejected_by': rejectedBy, 'current_target_driver_id': null}).eq('id', ride['id']);
      }
      setState(() { _rejectedRideIds.add(ride['id'].toString()); rides.removeWhere((r) => r['id'] == ride['id']); });
      await supabase.functions.invoke('send-ride-notification', body: {'ride_id': ride['id'], 'title': '🚕 Naujas užsakymas', 'message': 'Pasiėmimas: ${ride['pickup_address']}', 'lat': ride['pickup_lat'], 'lng': ride['pickup_lng']});
    } catch (_) {}
  }

  Future<void> updateRideStatus(String status) async {
    if (currentRide == null) return;
    if (status == 'completed') { await _handleRideCompletion(); return; }
    await supabase.from('rides').update({'status': status}).eq('id', currentRide!['id']);
    currentRide!['status'] = status;
    
    if (status == 'arrived') {
      _startWaitingTimer();
      // NAUJA: Pranešame keleiviui, kad vairuotojas atvyko
      try {
        await supabase.functions.invoke('notify-passenger', body: {
          'ride_id': currentRide!['id'],
          'title': '📍 Vairuotojas atvyko!',
          'message': 'Jūsų CityRide laukia paėmimo vietoje.',
        });
      } catch (_) {}
    } else {
      _stopWaitingTimer();
    }

    // Taisome navigacijos kryptį: arrived ir in_progress visada rodo į tikslą
    final target = (status == 'arrived' || status == 'in_progress') 
        ? currentRide!['destination_address'] 
        : currentRide!['pickup_address'];

    await drawRoute(currentPosition, target);
    setState(() => _isFollowingDriver = true);
  }

  void _startWaitingTimer() {
    _waitingSeconds = 0;
    _waitingTimer?.cancel();
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() { _waitingSeconds++; });
    });
  }

  void _stopWaitingTimer() {
    _waitingTimer?.cancel();
    _waitingSeconds = 0;
  }

  Future<void> _handleNoShow() async {
    if (currentRide == null) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.black)),
    );

    try {
      final rideId = currentRide!['id'];
      final fare = 3.00; // Standartinis mokestis už nepasirodymą
      final comm = fare * 0.10;
      final net = fare - comm;

      // 1. Įrašome uždarbį vairuotojui
      await supabase.from('driver_earnings').insert({
        'driver_id': driverId,
        'ride_id': rideId,
        'total_fare': fare,
        'commission': comm,
        'net_earnings': net,
        'type': 'cancellation_fee',
      });

      // 2. Iškviečiame Edge Function pinigų nurašymui
      await supabase.functions.invoke('charge-no-show', body: {
        'ride_id': rideId,
        'driver_id': driverId,
      });

      if (mounted) Navigator.pop(context);
      
      setState(() {
        currentRide = null;
        polylines.clear();
        _stopWaitingTimer();
      });
      
      fetchRides();
      
      if (mounted) {
        showDialog(context: context, builder: (_) => AlertDialog(
          title: const Text('Klientas nepasirodė'),
          content: const Text('Užsakymas atšauktas. Jums priskirtas 2.70€ kompensacinis mokestis.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('GERAI'))],
        ));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('No-show error: $e');
    }
  }

  Future<void> _handleRideCompletion() async {
    if (currentRide == null) return;
    final rideId = currentRide!['id'];
    final fare = double.tryParse(currentRide!['price'].toString()) ?? 0;
    final comm = fare * 0.10;
    final net = fare - comm;

    currentRide!['status'] = 'completed';
    WakelockPlus.disable(); // Išjungiame ekrano budėjimo rėžimą baigus kelionę

    try {
      // 1. Įrašome uždarbį į lentelę (kad iškart matytųsi pajamose)
      await supabase.from('driver_earnings').insert({
        'driver_id': driverId,
        'ride_id': rideId,
        'total_fare': fare,
        'commission': comm,
        'net_earnings': net,
        'type': 'ride',
      });

      // 2. Atnaujiname kelionės statusą
      await supabase.from('rides').update({'status': 'completed'}).eq('id', rideId);
      
      // 3. Iškviečiame Edge Function automatiniam apmokėjimui (Stripe)
      await supabase.functions.invoke('stripe-auto-charge', body: {'ride_id': rideId}); 
    } catch (e) {
      debugPrint('Ride completion error: $e');
    }

    _showEarningsDialog(fare, comm, net);
    setState(() { currentRide = null; polylines.clear(); });
    fetchRides();
  }

  Future<void> drawRoute(LatLng origin, String destinationAddress) async {
    try {
      final geoUrl = 'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(destinationAddress)}&key=$googleApiKey';
      final geoRes = await http.get(Uri.parse(geoUrl));
      final geoData = jsonDecode(geoRes.body);
      if (geoData['results'].isEmpty) return;
      final dest = LatLng(geoData['results'][0]['geometry']['location']['lat'], geoData['results'][0]['geometry']['location']['lng']);
      final result = await PolylinePoints().getRouteBetweenCoordinates(request: PolylineRequest(origin: PointLatLng(origin.latitude, origin.longitude), destination: PointLatLng(dest.latitude, dest.longitude), mode: TravelMode.driving), googleApiKey: googleApiKey);
      if (result.points.isNotEmpty) {
        setState(() {
          polylines.clear();
          polylines.add(Polyline(polylineId: const PolylineId('route'), points: result.points.map((p) => LatLng(p.latitude, p.longitude)).toList(), width: 14, color: const Color(0xFF2196F3), jointType: JointType.round, startCap: Cap.roundCap, endCap: Cap.roundCap));
        });
      }
    } catch (_) {}
  }

  void _showNotApprovedDialog() {
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Profilis nepatvirtintas'), content: const Text('Laukite patvirtinimo.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Gerai'))]));
  }

  Future<void> _showCancellationDialog(Map<String, dynamic>? cancelledRide) async {
    String message = 'Keleivis atšaukė kelionę';
    
    if (cancelledRide != null) {
      final res = await supabase.from('rides').select('cancellation_fee').eq('id', cancelledRide['id']).maybeSingle();
      if (res != null && res['cancellation_fee'] != null && (res['cancellation_fee'] as num) > 0) {
        final fee = (res['cancellation_fee'] as num).toDouble();
        message = 'Keleivis atšaukė kelionę po 3 min. Jums priskirtas €${(fee * 0.9).toStringAsFixed(2)} kompensacinis mokestis.';
      }
    }
    
    // Grįžtame į pagrindinį režimą
    setState(() {
      currentRide = null;
      polylines.clear();
      hadActiveRide = false;
      _isFollowingDriver = false;
      _stopWaitingTimer();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context, 
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Kelionė atšaukta', style: TextStyle(fontWeight: FontWeight.bold)), 
          content: Text(message), 
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  fetchRides(); // Iškart ieškome naujų užsakymų
                }, 
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                child: const Text('GERAI')
              )
            )
          ]
        )
      );
    });
  }

  void _showEarningsDialog(double fare, double comm, double net) {
    showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 16),
        const Text('Kelionė baigta', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Suma:'), Text('€${fare.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Komisinis:'), Text('-€${comm.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red))]),
        const Divider(height: 32),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Jūsų uždarbis:', style: TextStyle(fontSize: 18)), Text('€${net.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, color: Colors.green, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Gerai'))),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: loadingLocation ? const Center(child: CircularProgressIndicator(color: Colors.red)) : Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: currentPosition, zoom: 15),
          myLocationEnabled: true, myLocationButtonEnabled: false, trafficEnabled: true,
          buildingsEnabled: false,
          padding: EdgeInsets.only(top: currentRide != null ? 100 : 0, bottom: currentRide != null ? 100 : 0),
          markers: markers, polylines: polylines, style: mapStyle,
          onMapCreated: (c) { mapController = c; },
          onCameraMoveStarted: () { if (currentRide != null && _isFollowingDriver) setState(() => _isFollowingDriver = false); },
        ),
        
        // Floating Navigation Header
        if (currentRide != null) _buildPremiumNavHeader(),
        
        // Offline/Online Top Overlay
        if (currentRide == null) _buildTopOverlay(),

        // Bottom Action Card
        if (isWorking) (currentRide != null ? _buildPremiumBottomCard() : _buildRideQueue()),
        
        // FAB Controls
        if (currentRide != null) _buildMapControls(),
      ]),
      bottomNavigationBar: currentRide == null ? _buildBottomNav() : null,
    );
  }

  Widget _buildPremiumNavHeader() {
    final status = currentRide!['status'];
    final isToPickup = status == 'accepted' || status == 'arrived';
    final String targetAddr = isToPickup ? currentRide!['pickup_address'] : currentRide!['destination_address'];

    return Positioned(top: 60, left: 16, right: 16, child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)), child: Icon(isToPickup ? Icons.u_turn_left : Icons.navigation, color: Colors.white, size: 28)),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(targetAddr.split(',')[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(isToPickup ? 'Paėmimo vieta' : 'Tikslas', style: const TextStyle(color: Colors.white60, fontSize: 13)),
        ])),
        if (etaText.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)), child: Text(etaText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
      ]),
    ));
  }

  Widget _buildPremiumBottomCard() {
    final status = currentRide!['status'];
    String statusText = "Važiuojama pas klientą";
    if (status == 'arrived') statusText = "Vairuotojas atvyko";
    if (status == 'in_progress') statusText = "Kelionė vyksta";

    return Positioned(left: 0, right: 0, bottom: 0, child: Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 34),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 15), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
        Text(statusText, style: const TextStyle(fontSize: 16, color: Colors.black54, fontWeight: FontWeight.w500)),
        const SizedBox(height: 5),
        Text(currentRide!['passenger_name'] ?? 'Keleivis', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        if (status == 'arrived')
          Container(
            margin: const EdgeInsets.only(bottom: 15),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _waitingSeconds >= 180 ? 'Galite atšaukti' : 'Laukimas: ${(_waitingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_waitingSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                ),
                if (_waitingSeconds >= 180)
                  GestureDetector(
                    onTap: _handleNoShow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                      child: const Text('KLIENTAS NEPASIRODĖ', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
        Row(children: [
          _circleButton(Icons.call, Colors.green, () async {
            final phone = currentRide?['passenger_phone']?.toString();
            if (phone != null && phone.isNotEmpty) {
              final Uri url = Uri(
                scheme: 'tel',
                path: phone.replaceAll(RegExp(r'[^0-9+]'), ''),
              );
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            }
          }),
          const SizedBox(width: 10),
          _circleButton(Icons.chat_bubble_outline, Colors.blue, () {
            if (currentRide != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatPage(
                    rideId: currentRide!['id'],
                    otherName: currentRide!['passenger_name'] ?? 'Keleivis',
                  ),
                ),
              );
            }
          }),
          const SizedBox(width: 10),
          Expanded(child: SizedBox(height: 60, child: ElevatedButton(onPressed: _nextStep, style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 0), child: Text(status == 'accepted' ? 'ATVYKAU' : (status == 'arrived' ? 'PRADĖTI' : 'BAIGTI'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1))))),
          const SizedBox(width: 10),
          _circleButton(Icons.map_outlined, Colors.orange, _openNav),
        ]),
      ]),
    ));
  }

  Widget _circleButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Container(width: 54, height: 54, decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 26)));
  }

  Widget _buildMapControls() {
    return Positioned(right: 16, bottom: 220, child: Column(children: [
      if (!_isFollowingDriver) _mapFab(Icons.navigation, () => setState(() => _isFollowingDriver = true)),
      const SizedBox(height: 12),
      _mapFab(Icons.layers_outlined, () {}),
    ]));
  }

  Widget _mapFab(IconData icon, VoidCallback onTap) {
    return FloatingActionButton(mini: true, backgroundColor: Colors.white, elevation: 4, onPressed: onTap, child: Icon(icon, color: Colors.black87));
  }

  Widget _buildTopOverlay() {
    return Positioned(top: 58, left: 16, right: 16, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      GestureDetector(onLongPress: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDriversPage())), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]), child: const Text('CityRide', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black)))),
      GestureDetector(onTap: toggleWorking, child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), decoration: BoxDecoration(color: isWorking ? Colors.green : Colors.black, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)]), child: Text(isWorking ? 'ONLINE' : 'OFFLINE', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
    ]));
  }

  Widget _buildRideQueue() {
    if (rides.isEmpty) return const SizedBox();
    final ride = rides.first;
    return Positioned(left: 16, right: 16, bottom: 20, child: Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, spreadRadius: 5)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (incomingRideEta != null) Container(margin: const EdgeInsets.only(bottom: 15), width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)), child: Text('Iki kliento $incomingRideEta', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('NAUJAS UŽSAKYMAS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)), 
            Text(ride['passenger_name'] ?? 'Keleivis', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20), maxLines: 1)
          ])),
          Text('€${double.tryParse(ride['price'].toString())?.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 20),
        _buildAddressRow(Icons.circle, ride['pickup_address'] ?? '', Colors.green),
        const SizedBox(height: 8),
        _buildAddressRow(Icons.location_on, ride['destination_address'] ?? '', Colors.red),
        const SizedBox(height: 25),
        Row(children: [
          Expanded(child: TextButton(onPressed: () => rejectRide(ride), child: const Text('ATMESTI', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)))),
          const SizedBox(width: 15),
          Expanded(flex: 2, child: ElevatedButton(onPressed: () => acceptRide(ride), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 5, padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text('PRIIMTI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)))),
        ]),
      ])));
  }

  Widget _buildAddressRow(IconData icon, String text, Color color) {
    return Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 12), Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)))]);
  }

  void _openNav() async {
    final addr = currentRide!['status'] == 'accepted' ? currentRide!['pickup_address'] : currentRide!['destination_address'];
    final driver = await supabase.from('drivers').select('preferred_nav_app').eq('id', driverId).single();
    final url = driver['preferred_nav_app'] == 'Google Maps' ? 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addr)}' : 'https://waze.com/ul?q=${Uri.encodeComponent(addr)}&navigate=yes';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  void _nextStep() => updateRideStatus(currentRide!['status'] == 'accepted' ? 'arrived' : (currentRide!['status'] == 'arrived' ? 'in_progress' : 'completed'));

  Widget _buildBottomNav() {
    return Container(height: 85, decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xffEEEEEE)))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _buildBottomItem(Icons.analytics_outlined, 'Pajamos', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PajamosPage()))),
        _buildBottomItem(Icons.newspaper_outlined, 'Naujienos', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewsPage()))),
        _buildBottomItem(Icons.person_outline, 'Profilis', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverProfilePage()))),
      ]));
  }

  Widget _buildBottomItem(IconData icon, String title, VoidCallback? onTap) {
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: Colors.black, size: 26), const SizedBox(height: 4), Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))]));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed && isWorking) fetchRides(); }

  @override
  void dispose() { _positionStream?.cancel(); _ridesRefreshTimer?.cancel(); ridesChannel?.unsubscribe(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
}
