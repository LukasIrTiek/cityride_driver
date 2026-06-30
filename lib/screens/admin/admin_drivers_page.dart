import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../services/invoice_service.dart';

class AdminDriversPage extends StatefulWidget {
  const AdminDriversPage({super.key});

  @override
  State<AdminDriversPage> createState() => _AdminDriversPageState();
}

class _AdminDriversPageState extends State<AdminDriversPage> {
  final supabase = Supabase.instance.client;

  List drivers = [];
  Map<String, dynamic> driverStats = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchDrivers();
  }

  Future<void> fetchDrivers() async {
    setState(() => isLoading = true);
    try {
      final response = await supabase.from('drivers').select();
      final earnings = await supabase.from('driver_earnings').select();

      Map<String, dynamic> stats = {};
      for (var d in response) {
        String id = d['id'];
        List dEarnings = earnings.where((e) => e['driver_id'] == id).toList();
        double totalFare = 0;
        double totalComm = 0;
        for (var e in dEarnings) {
          totalFare += (e['total_fare'] ?? 0).toDouble();
          totalComm += (e['commission'] ?? 0).toDouble();
        }
        stats[id] = {
          'earnings': dEarnings,
          'totalFare': totalFare,
          'totalComm': totalComm,
          'ivNumber': d['iv_number'] ?? '',
        };
      }

      setState(() {
        drivers = response;
        driverStats = stats;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> updateStatus(String id, String status) async {
    await supabase.from('drivers').update({'verification_status': status}).eq('id', id);
    fetchDrivers();
  }

  Future<void> openDriverDocuments(String driverId) async {
    final docs = await supabase.from('driver_documents').select().eq('driver_id', driverId);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const Padding(padding: EdgeInsets.all(20), child: Text('Vairuotojo dokumentai', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            Expanded(
              child: docs.isEmpty 
                ? const Center(child: Text('Dokumentų nėra'))
                : GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 30, childAspectRatio: 0.75),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      String dates = "";
                      if (doc['valid_from'] != null && doc['valid_until'] != null) {
                        dates = "\nNuo: ${doc['valid_from'].toString().split('T')[0]}\nIki: ${doc['valid_until'].toString().split('T')[0]}";
                      }
                      return Column(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                image: DecorationImage(image: NetworkImage(doc['file_url']), fit: BoxFit.cover),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(doc['document_type'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          if (dates.isNotEmpty)
                            Text(dates, style: const TextStyle(fontSize: 10, color: Colors.red), textAlign: TextAlign.center),
                        ],
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double platformTotalFare = 0;
    double platformTotalComm = 0;
    driverStats.forEach((key, value) {
      platformTotalFare += value['totalFare'] ?? 0;
      platformTotalComm += value['totalComm'] ?? 0;
    });

    return Scaffold(
      backgroundColor: const Color(0xffF8F9FA),
      appBar: AppBar(
        title: const Text('Vairuotojų valdymas', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [IconButton(onPressed: fetchDrivers, icon: const Icon(Icons.refresh, color: Colors.black))],
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: drivers.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      const Text('Bendra platformos statistika', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statItem('Bendra apyvarta', '€${platformTotalFare.toStringAsFixed(2)}', Colors.white),
                          _statItem('Viso komisinių', '€${platformTotalComm.toStringAsFixed(2)}', Colors.green),
                        ],
                      ),
                    ],
                  ),
                );
              }
              final driver = drivers[index - 1];
              final status = driver['verification_status'] ?? 'pending';
              final stats = driverStats[driver['id']];
              final isApproved = status == 'approved';

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(driver['full_name'] ?? 'Be vardo', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                Text(driver['email'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isApproved ? Colors.green.shade50 : (status == 'rejected' ? Colors.red.shade50 : Colors.orange.shade50),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(color: isApproved ? Colors.green : (status == 'rejected' ? Colors.red : Colors.orange), fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _infoRow(Icons.phone, 'Telefonas', driver['phone'] ?? '-'),
                          _infoRow(Icons.assignment_ind, 'IV numeris', driver['iv_number'] ?? '-'),
                          _infoRow(Icons.directions_car, 'Automobilis', driver['car_model'] ?? '-'),
                          _infoRow(Icons.numbers, 'Valst. numeriai', driver['plate_number'] ?? '-'),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(20),
                      color: Colors.grey.shade50,
                      child: Row(
                        children: [
                          Expanded(child: _statItem('Apyvarta', '€${(stats?['totalFare'] ?? 0).toStringAsFixed(2)}', Colors.black)),
                          Container(width: 1, height: 30, color: Colors.grey.shade300),
                          Expanded(child: _statItem('Komisinis (10%)', '€${(stats?['totalComm'] ?? 0).toStringAsFixed(2)}', Colors.red)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => openDriverDocuments(driver['id']),
                                  icon: const Icon(Icons.description_outlined, size: 18),
                                  label: const Text('DOKUMENTAI'),
                                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton(
                                onPressed: () async {
                                  if (stats == null || stats['earnings'].isEmpty) return;
                                  await InvoiceService.generateMonthlyCommissionReport(
                                    earnings: stats['earnings'],
                                    month: DateFormat('MMMM yyyy').format(DateTime.now()),
                                    driverName: driver['full_name'] ?? 'Vairuotojas',
                                    ivNumber: stats['ivNumber'],
                                  );
                                },
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.blue),
                              ),
                              IconButton(
                                onPressed: () async {
                                  if (stats == null || stats['totalComm'] == 0) return;
                                  await InvoiceService.syncCommissionToSitePro(
                                    driverName: driver['full_name'] ?? 'Vairuotojas',
                                    month: DateFormat('MMMM yyyy').format(DateTime.now()),
                                    amount: stats['totalComm'],
                                  );
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nusiųsta į Site.pro')));
                                },
                                icon: const Icon(Icons.cloud_upload_outlined, color: Colors.orange),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: isApproved ? null : () => updateStatus(driver['id'], 'approved'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), elevation: 0),
                                  child: const Text('PATVIRTINTI PROFILĮ', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                              if (isApproved) ...[
                                const SizedBox(width: 10),
                                IconButton(onPressed: () => updateStatus(driver['id'], 'pending'), icon: const Icon(Icons.lock_open, color: Colors.grey)),
                              ],
                              if (!isApproved) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: status == 'rejected' ? null : () => updateStatus(driver['id'], 'rejected'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), elevation: 0),
                                    child: const Text('ATMESTI', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 10),
          Text('$label:', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 5),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}
