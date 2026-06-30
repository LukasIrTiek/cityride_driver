import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/invoice_service.dart';
import 'driver_trips_page.dart';

class PajamosPage extends StatefulWidget {
  const PajamosPage({super.key});

  @override
  State<PajamosPage> createState() => _PajamosPageState();
}

class _PajamosPageState extends State<PajamosPage> {
  final supabase = Supabase.instance.client;

  double totalFare = 0;
  double totalCommission = 0;
  double totalNet = 0;

  double weeklyNet = 0;
  double monthlyNet = 0;

  double weeklyFare = 0;
  double weeklyCommission = 0;

  double monthlyFare = 0;
  double monthlyCommission = 0;

  double onlineHours = 0;

  int completedRides = 0;
  int cancellations = 0;
  String driverName = '';
  String ivNumber = '';

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await loadEarnings();
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> loadEarnings() async {
    setState(() {
      isLoading = true;
    });

    final user = supabase.auth.currentUser;
    if (user != null) {
      final driver = await supabase.from('drivers').select('full_name, iv_number').eq('id', user.id).maybeSingle();
      driverName = driver?['full_name'] ?? 'Vairuotojas';
      ivNumber = driver?['iv_number'] ?? '';
    } else {
      setState(() => isLoading = false);
      return;
    }

    final response = await supabase
        .from('driver_earnings')
        .select()
        .eq('driver_id', user.id);

    double fare = 0;
    double commission = 0;
    double net = 0;

    double weekly = 0;
    double monthly = 0;

    double weeklyFareTotal = 0;
    double weeklyCommissionTotal = 0;

    double monthlyFareTotal = 0;
    double monthlyCommissionTotal = 0;

    int completed = 0;
    int cancelled = 0;

    for (final item in response) {
      if (item['type'] == 'cancellation_fee') {
        cancelled++;
      } else {
        completed++;
      }

      fare += (item['total_fare'] ?? 0).toDouble();
      commission += (item['commission'] ?? 0).toDouble();
      net += (item['net_earnings'] ?? 0).toDouble();

      final createdAt = DateTime.parse(item['created_at']).toLocal();
      final now = DateTime.now();

      if (now.difference(createdAt).inDays <= 7) {
        weekly += (item['net_earnings'] ?? 0).toDouble();
        weeklyFareTotal += (item['total_fare'] ?? 0).toDouble();
        weeklyCommissionTotal += (item['commission'] ?? 0).toDouble();
      }

      if (createdAt.month == now.month) {
        monthly += (item['net_earnings'] ?? 0).toDouble();
        monthlyFareTotal += (item['total_fare'] ?? 0).toDouble();
        monthlyCommissionTotal += (item['commission'] ?? 0).toDouble();
      }
    }

    if (!mounted) return;

    setState(() {
      totalFare = fare;
      totalCommission = commission;
      totalNet = net;
      weeklyNet = weekly;
      monthlyNet = monthly;
      weeklyFare = weeklyFareTotal;
      weeklyCommission = weeklyCommissionTotal;
      monthlyFare = monthlyFareTotal;
      monthlyCommission = monthlyCommissionTotal;
      completedRides = completed;
      cancellations = cancelled;
      onlineHours = (completed + cancelled) * 0.8;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pajamos'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () async {
              final month = DateFormat('MMMM yyyy').format(DateTime.now());
              final earnings = await supabase.from('driver_earnings').select();
              await InvoiceService.generateMonthlyCommissionReport(
                earnings: earnings,
                month: month,
                driverName: driverName,
                ivNumber: ivNumber,
              );
            },
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Mėnesinė ataskaita',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadEarnings,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Visas uždarbis', style: TextStyle(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 14),
                        Text(
                          '€${totalFare.toStringAsFixed(2)} - €${totalCommission.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text('Bendra apyvarta - Komisiniai', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 12),
                        const Text('=', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text(
                          '€${totalNet.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.green, fontSize: 40, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text('Neto uždarbis', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverTripsPage())),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(14)),
                            child: const Icon(Icons.local_taxi, color: Colors.green),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Kelionės / Atšauktos',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$completedRides / $cancellations',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Statistika', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        _buildStatRow('Ši savaitė', '€${weeklyNet.toStringAsFixed(2)}'),
                        const SizedBox(height: 14),
                        _buildStatRow('Šis mėnuo', '€${monthlyNet.toStringAsFixed(2)}'),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Viso komisinių (10%)', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('€${totalCommission.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildStatRow('Online valandos', '${onlineHours.toStringAsFixed(1)}h'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 220,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            isCurved: true,
                            color: Colors.green,
                            barWidth: 5,
                            spots: [
                              const FlSpot(0, 20),
                              const FlSpot(1, 35),
                              const FlSpot(2, 28),
                              const FlSpot(3, 60),
                              const FlSpot(4, 48),
                              const FlSpot(5, 75),
                              FlSpot(6, totalNet),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text(value)],
    );
  }
}
