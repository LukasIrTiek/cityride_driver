import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../delete_account_page.dart';
import 'auth_gate.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key});

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  final ImagePicker picker = ImagePicker();
  final supabase = Supabase.instance.client;

  String verificationStatus = '';
  bool profileLocked = false;

  final fullNameController = TextEditingController();
  final phoneController = TextEditingController();
  final ivNumberController = TextEditingController();
  final plateController = TextEditingController();
  final bankOwnerController = TextEditingController();
  final bankIbanController = TextEditingController();

  bool autoNav = false;
  String preferredNavApp = 'Waze';
  String profilePhoto = '';
  
  Map<String, bool> uploadedDocs = {};

  final Map<String, List<String>> carBrands = {
    'Audi': ['A1', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'Q2', 'Q3', 'Q5', 'Q7', 'Q8', 'e-tron'],
    'BMW': ['1 Series', '2 Series', '3 Series', '4 Series', '5 Series', '7 Series', 'X1', 'X3', 'X5', 'X6', 'i3', 'i4', 'iX'],
    'Toyota': ['Yaris', 'Corolla', 'Avensis', 'Prius', 'Camry', 'C-HR', 'RAV4', 'Highlander', 'Land Cruiser'],
    'Volkswagen': ['Polo', 'Golf', 'Passat', 'Arteon', 'T-Roc', 'Tiguan', 'Touareg', 'ID.3', 'ID.4', 'ID.Buzz', 'Transporter'],
    'Mercedes-Benz': ['A-Class', 'C-Class', 'E-Class', 'S-Class', 'CLA', 'CLS', 'GLA', 'GLC', 'GLE', 'GLS', 'EQE', 'EQS'],
    'Skoda': ['Fabia', 'Scala', 'Octavia', 'Superb', 'Kamiq', 'Karoq', 'Kodiaq', 'Enyaq'],
    'Ford': ['Fiesta', 'Focus', 'Mondeo', 'Mustang', 'Puma', 'Kuga', 'Explorer', 'Transit'],
    'Opel': ['Corsa', 'Astra', 'Insignia', 'Mokka', 'Grandland', 'Combo', 'Vivaro'],
    'Volvo': ['S60', 'S90', 'V60', 'V90', 'XC40', 'XC60', 'XC90'],
    'Lexus': ['IS', 'ES', 'LS', 'UX', 'NX', 'RX', 'RZ'],
    'Honda': ['Civic', 'Accord', 'CR-V', 'HR-V', 'Jazz'],
    'Hyundai': ['i10', 'i20', 'i30', 'Ioniq', 'Kona', 'Tucson', 'Santa Fe'],
    'Kia': ['Picanto', 'Ceed', 'Sportage', 'Sorento', 'Niro', 'EV6'],
  };

  final List<String> years = List.generate(35, (index) => (DateTime.now().year - index).toString());

  String? selectedMake;
  String? selectedModel;
  String? selectedYear;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      
      final driverData = await supabase.from('drivers').select().eq('id', user.id).single();
      final docs = await supabase.from('driver_documents').select().eq('driver_id', user.id);

      if (mounted) {
        setState(() {
          profilePhoto = driverData['profile_photo'] ?? '';
          verificationStatus = (driverData['verification_status'] ?? '').toString();
          profileLocked = verificationStatus == 'approved' || verificationStatus == 'deletion_pending';
          
          fullNameController.text = driverData['full_name'] ?? '';
          phoneController.text = driverData['phone'] ?? '';
          ivNumberController.text = driverData['iv_number'] ?? '';
          plateController.text = driverData['plate_number'] ?? '';
          bankOwnerController.text = driverData['bank_owner_name'] ?? '';
          bankIbanController.text = driverData['bank_iban'] ?? '';
          autoNav = driverData['auto_nav'] ?? false;
          preferredNavApp = driverData['preferred_nav_app'] ?? 'Waze';

          uploadedDocs.clear();
          for (var d in docs) {
            uploadedDocs[d['document_type']] = true;
          }

          String carInfo = driverData['car_model'] ?? '';
          if (carInfo.contains('|')) {
            List<String> parts = carInfo.split('|');
            if (parts.length >= 1) selectedMake = carBrands.containsKey(parts[0].trim()) ? parts[0].trim() : null;
            if (parts.length >= 2 && selectedMake != null && carBrands[selectedMake!]!.contains(parts[1].trim())) selectedModel = parts[1].trim();
            if (parts.length >= 3 && years.contains(parts[2].trim())) selectedYear = parts[2].trim();
          }
        });
      }
    } catch (e) {
      debugPrint('LoadData error: $e');
    }
  }

  Future<void> _pickAndUpload(String type) async {
    if (profileLocked) return;
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      final file = File(image.path);
      final fileExt = p.extension(image.path).replaceAll('.', '').toLowerCase();
      String sanitizedType = type.toLowerCase().replaceAll('ą', 'a').replaceAll('č', 'c').replaceAll('ę', 'e').replaceAll('ė', 'e').replaceAll('į', 'i').replaceAll('š', 's').replaceAll('ų', 'u').replaceAll('ū', 'u').replaceAll('ž', 'z').replaceAll(' ', '_');
      final fileName = '${supabase.auth.currentUser!.id}_${sanitizedType}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await supabase.storage.from('driver-documents').upload(fileName, file, fileOptions: const FileOptions(upsert: true));
      final imageUrl = supabase.storage.from('driver-documents').getPublicUrl(fileName);

      await supabase.from('driver_documents').upsert({
        'driver_id': supabase.auth.currentUser!.id,
        'document_type': type,
        'file_url': imageUrl,
      }, onConflict: 'driver_id, document_type');

      if (type == 'Profilio nuotrauka') {
        await supabase.from('drivers').update({'profile_photo': imageUrl}).eq('id', supabase.auth.currentUser!.id);
      }

      await loadData();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Upload error: $e');
    }
  }

  Widget buildDocItem(String title) {
    bool isUploaded = uploadedDocs[title] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isUploaded ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isUploaded ? Colors.green.shade200 : Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(isUploaded ? Icons.check_circle : Icons.error_outline, color: isUploaded ? Colors.green : Colors.red),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isUploaded ? Colors.green.shade900 : Colors.red.shade900))),
          if (!profileLocked)
            TextButton(
              onPressed: () => _pickAndUpload(title),
              child: Text(isUploaded ? 'PAKEISTI' : 'ĮKELTI (PRIVALOMA)', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Profilio nustatymai', style: TextStyle(fontWeight: FontWeight.bold)), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(radius: 50, backgroundColor: Colors.grey.shade200, backgroundImage: profilePhoto.isNotEmpty ? NetworkImage(profilePhoto) : null),
                      if (!profileLocked)
                        Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: () => _pickAndUpload('Profilio nuotrauka'), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: profilePhoto.isEmpty ? Colors.red : Colors.black, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 18)))),
                    ],
                  ),
                  if (profilePhoto.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nuotrauka privaloma!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12))),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text('Navigacijos nustatymai', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Automatinė navigacija', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: const Text('Atsidaro iškart priėmus užsakymą', style: TextStyle(fontSize: 12)),
                    value: autoNav,
                    activeColor: Colors.black,
                    onChanged: (val) => setState(() => autoNav = val),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Pasirinkta programėlė', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: DropdownButton<String>(
                      value: preferredNavApp,
                      underline: const SizedBox(),
                      items: ['Waze', 'Google Maps'].map((app) => DropdownMenuItem(value: app, child: Text(app))).toList(),
                      onChanged: (val) => setState(() => preferredNavApp = val!),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text('Asmeninė informacija (Privaloma)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(controller: fullNameController, enabled: !profileLocked, decoration: InputDecoration(labelText: 'Vardas Pavardė *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: phoneController, enabled: !profileLocked, decoration: InputDecoration(labelText: 'Telefonas *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: ivNumberController, enabled: !profileLocked, decoration: InputDecoration(labelText: 'Individualios veiklos Nr. *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 30),
            const Text('Banko informacija (Privaloma)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(controller: bankOwnerController, enabled: !profileLocked, decoration: InputDecoration(labelText: 'Sąskaitos savininkas *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: bankIbanController, enabled: !profileLocked, decoration: InputDecoration(labelText: 'Sąskaitos numeris (IBAN) *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            buildDocItem('Banko išrašas'),
            const SizedBox(height: 30),
            const Text('Vairuotojo dokumentai (Privaloma)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            buildDocItem('Vairuotojo pažymėjimas (Priekis)'),
            buildDocItem('Vairuotojo pažymėjimas (Galas)'),
            buildDocItem('Asmens tapatybė'),
            buildDocItem('Individuali veikla'),
            buildDocItem('Leidimas vežti keleivius'),
            const SizedBox(height: 30),
            const Text('Automobilio informacija (Privaloma)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedMake,
                    decoration: const InputDecoration(labelText: 'Markė *'),
                    items: carBrands.keys.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: profileLocked ? null : (v) => setState(() { selectedMake = v; selectedModel = null; }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedModel,
                    decoration: const InputDecoration(labelText: 'Modelis *'),
                    items: selectedMake == null ? [] : carBrands[selectedMake!]!.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: profileLocked ? null : (v) => setState(() => selectedModel = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedYear,
                    decoration: const InputDecoration(labelText: 'Gamybos metai *'),
                    items: years.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                    onChanged: profileLocked ? null : (v) => setState(() => selectedYear = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: plateController,
                    enabled: !profileLocked,
                    decoration: const InputDecoration(labelText: 'Valstybiniai numeriai *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  buildDocItem('Automobilio dokumentas'),
                  buildDocItem('Draudimas'),
                  buildDocItem('Technikinė'),
                ],
              ),
            ),
            const SizedBox(height: 40),
            if (!profileLocked)
              SizedBox(
                width: double.infinity, 
                height: 60, 
                child: ElevatedButton(
                  onPressed: () async {
                    List<String> missing = [];
                    if (fullNameController.text.trim().isEmpty) missing.add('Vardas Pavardė');
                    if (phoneController.text.trim().isEmpty) missing.add('Telefonas');
                    if (ivNumberController.text.trim().isEmpty) missing.add('IV numeris');
                    if (bankOwnerController.text.trim().isEmpty) missing.add('Banko sąskaitos savininkas');
                    if (bankIbanController.text.trim().isEmpty) missing.add('Banko IBAN');
                    if (plateController.text.trim().isEmpty) missing.add('Valstybiniai numeriai');
                    if (selectedMake == null) missing.add('Markė');
                    if (selectedModel == null) missing.add('Modelis');
                    if (selectedYear == null) missing.add('Metai');
                    if (profilePhoto.isEmpty) missing.add('Profilio nuotrauka');
                    
                    final requiredDocs = [
                      'Vairuotojo pažymėjimas (Priekis)', 'Vairuotojo pažymėjimas (Galas)', 
                      'Asmens tapatybė', 'Individuali veikla', 'Leidimas vežti keleivius',
                      'Automobilio dokumentas', 'Draudimas', 'Technikinė', 'Banko išrašas'
                    ];
                    for(var doc in requiredDocs) {
                      if (uploadedDocs[doc] != true) missing.add('Dokumentas: $doc');
                    }

                    if (missing.isNotEmpty) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Trūksta duomenų', style: TextStyle(fontWeight: FontWeight.bold)),
                          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: missing.map((e) => Text('• $e')).toList())),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('GERAI'))],
                        ),
                      );
                      return;
                    }

                    try {
                      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
                      String carModelStr = '${selectedMake ?? ''}|${selectedModel ?? ''}|${selectedYear ?? ''}';
                      await supabase.from('drivers').update({
                        'full_name': fullNameController.text.trim(),
                        'phone': phoneController.text.trim(),
                        'iv_number': ivNumberController.text.trim(),
                        'plate_number': plateController.text.trim(),
                        'bank_owner_name': bankOwnerController.text.trim(),
                        'bank_iban': bankIbanController.text.trim(),
                        'car_model': carModelStr,
                        'verification_status': 'pending',
                        'auto_nav': autoNav,
                        'preferred_nav_app': preferredNavApp,
                      }).eq('id', supabase.auth.currentUser!.id);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text('Pateikta patvirtinimui!')));
                        loadData();
                      }
                    } catch (e) {
                      if (mounted) Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Klaida išsaugant: $e')));
                    }
                  }, 
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
                  child: const Text('IŠSAUGOTI VISKĄ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                )
              ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}
