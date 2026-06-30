import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverTripsPage extends StatefulWidget {
  const DriverTripsPage({super.key});

  @override
  State<DriverTripsPage> createState() => _DriverTripsPageState();
}

class _DriverTripsPageState extends State<DriverTripsPage> {
  final supabase = Supabase.instance.client;

  List trips = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadTrips();
  }

  Future<void> loadTrips() async {
    try {
      final driverId = supabase.auth.currentUser!.id;

      final earnings = await supabase
          .from('driver_earnings')
          .select()
          .eq('driver_id', driverId)
          .order(
        'created_at',
        ascending: false,
      );

      List result = [];

      for (final item in earnings) {
        final ride = await supabase
            .from('rides')
            .select()
            .eq('id', item['ride_id'])
            .maybeSingle();

        result.add({
          ...item,
          'ride': ride,
        });
      }

      if (!mounted) return;

      setState(() {
        trips = result;
        loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    }
  }

  String formatDate(String? date) {
    if (date == null) return '';

    try {
      // Užtikriname, kad laikas būtų traktuojamas kaip UTC, jei nėra nurodyta kitaip
      String dateStr = date;
      if (!dateStr.endsWith('Z') && !dateStr.contains('+')) {
        dateStr = '${dateStr.replaceFirst(' ', 'T')}Z';
      }
      final dt = DateTime.parse(dateStr).toLocal();

      return '${dt.day.toString().padLeft(2, '0')}.'
          '${dt.month.toString().padLeft(2, '0')}.'
          '${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Kelionių istorija'),
        centerTitle: true,
      ),
      body: loading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : trips.isEmpty
          ? const Center(
        child: Text('Kelionių nėra'),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: trips.length,
        itemBuilder: (context, index) {
          final trip = trips[index];
          final ride = trip['ride'];
          final isCancellation = trip['type'] == 'cancellation_fee';

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        formatDate(
                          ride?['created_at'] ?? trip['created_at'],
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (isCancellation)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          'ATŠAUKIMAS',
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                const Text(
                  '📍 Iš',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  ride?['pickup_address'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                const Center(
                  child: Icon(
                    Icons.alt_route,
                    color: Colors.green,
                    size: 28,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  '🎯 Į',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  ride?['destination_address'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const Divider(height: 30),

                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Kelionės kaina',
                    ),
                    Text(
                      '€${((trip['total_fare'] ?? 0) as num).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Komisinis',
                    ),
                    Text(
                      '- €${((trip['commission'] ?? 0) as num).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Jūsų uždarbis',
                    ),
                    Text(
                      '€${((trip['net_earnings'] ?? 0) as num).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}