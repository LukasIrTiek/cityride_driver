import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../services/document_service.dart';

class MyDocumentsPage extends StatefulWidget {
  const MyDocumentsPage({super.key});

  @override
  State<MyDocumentsPage> createState() => _MyDocumentsPageState();
}

class _MyDocumentsPageState extends State<MyDocumentsPage> {
  List<Map<String, dynamic>> driverDocs = [];
  bool isLoading = true;

  final List<String> requiredDocTypes = [
    'Asmens tapatybės kortelė arba pasas',
    'Vairuotojo pažymėjimas',
    'Asmenukė (Selfie)',
    'Transporto priemonės registracijos liudijimas',
    'Civilinės atsakomybės draudimas',
    'Techninė apžiūra'
  ];

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    setState(() => isLoading = true);
    try {
      final docs = await DocumentService.getDriverDocuments();
      setState(() => driverDocs = docs);
    } catch (e) {
      debugPrint('Load docs error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Color _getStatusColor(String status, DateTime? expiryDate) {
    if (expiryDate != null) {
      final daysToExpiry = expiryDate.difference(DateTime.now()).inDays;
      if (daysToExpiry < 0) return Colors.red;
      if (daysToExpiry <= 30) return Colors.orange;
    }

    switch (status) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      case 'pending': return Colors.blue;
      default: return Colors.grey;
    }
  }

  String _getStatusText(String status, DateTime? expiryDate) {
    if (expiryDate != null && expiryDate.isBefore(DateTime.now())) return 'Pasibaigęs';
    if (expiryDate != null && expiryDate.difference(DateTime.now()).inDays <= 30) return 'Baigia galioti';

    switch (status) {
      case 'approved': return 'Patvirtintas';
      case 'rejected': return 'Atmestas';
      case 'pending': return 'Laukia patvirtinimo';
      default: return 'Nepateiktas';
    }
  }

  Future<void> _pickAndUpload(String type) async {
    final ImagePicker picker = ImagePicker();
    
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Fotografuoti'), onTap: () => Navigator.pop(context, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galerija'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ],
        ),
      ),
    );

    if (source == null) return;
    final pickedFile = await picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile == null) return;

    // Optional: Ask for doc number and dates
    DateTime? expiry;
    if (type != 'Asmenukė (Selfie)') {
      expiry = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 365)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
        helpText: 'Pasirinkite dokumento galiojimo pabaigą',
      );
    }

    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      await DocumentService.uploadDocument(
        type: type,
        file: File(pickedFile.path),
        expiryDate: expiry,
      );
      await _loadDocs();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dokumentas įkeltas sėkmingai')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Klaida: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mano dokumentai'), centerTitle: true),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: requiredDocTypes.length,
              itemBuilder: (context, index) {
                final type = requiredDocTypes[index];
                final doc = driverDocs.firstWhere((d) => d['document_type'] == type, orElse: () => {});
                
                final status = doc['status'] ?? 'none';
                final DateTime? expiry = doc['expiry_date'] != null ? DateTime.parse(doc['expiry_date']) : null;
                final color = _getStatusColor(status, expiry);

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: color.withOpacity(0.5), width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.description, color: color),
                            const SizedBox(width: 12),
                            Expanded(child: Text(type, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                            _statusBadge(status, expiry),
                          ],
                        ),
                        if (expiry != null) ...[
                          const SizedBox(height: 8),
                          Text('Galioja iki: ${DateFormat('yyyy-MM-dd').format(expiry)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        ],
                        if (doc['admin_comment'] != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                            child: Text('Komentaras: ${doc['admin_comment']}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            if (status != 'none')
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () { /* View logic */ },
                                  child: const Text('Peržiūrėti'),
                                ),
                              ),
                            if (status != 'none') const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: (status == 'approved') ? null : () => _pickAndUpload(type),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: status == 'none' ? Colors.black : null,
                                  foregroundColor: status == 'none' ? Colors.white : null,
                                ),
                                child: Text(status == 'none' ? 'Įkelti' : 'Pakeisti'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _statusBadge(String status, DateTime? expiry) {
    final text = _getStatusText(status, expiry);
    final color = _getStatusColor(status, expiry);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
