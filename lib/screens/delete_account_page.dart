import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_gate.dart';

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final supabase = Supabase.instance.client;
  bool _isRequesting = false;

  Future<void> _requestDeletion() async {
    setState(() => _isRequesting = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Vairuotojams nustatome būseną 'deletion_pending'
      // Administratorius pamatys šį prašymą ir galės patvirtinti ištrynimą
      await supabase.from('drivers').update({
        'verification_status': 'deletion_pending',
      }).eq('id', userId);

      // Atsijungiame, nes vairuotojas nebegali naudotis programėle kol laukiama
      await supabase.auth.signOut();

      if (!mounted) return;
      
      // Rodome pranešimą ir nukreipiame į AuthGate
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Prašymas išsiųstas'),
          content: const Text('Jūsų prašymas ištrinti paskyrą gautas. Administratorius peržiūrės jį per 24 valandas. Paskyra bus ištrinta po patvirtinimo.'),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => AuthGate()),
                  (route) => false,
                );
              },
              child: const Text('GERAI'),
            ),
          ],
        ),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Klaida siunčiant prašymą: $e')),
      );
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ar tikrai norite ištrinti paskyrą?'),
        content: const Text('Jūsų prašymas bus perduotas administracijai. Po patvirtinimo visi jūsų duomenys bus pašalinti.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ATŠAUKTI'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestDeletion();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('PATVIRTINTI'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ištrinti paskyrą'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PASKYROS IŠTRYNIMAS',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Text(
              'Kaip tai veikia vairuotojams?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Dėl saugumo ir mokestinių prievolių, vairuotojų paskyros nėra ištrinamos akimirksniu.\n\n'
              '1. Jūs pateikiate prašymą.\n'
              '2. Administratorius patikrina, ar nėra nebaigtų atsiskaitymų.\n'
              '3. Prašymas patvirtinamas ir paskyra pašalinama per 24 valandas.\n'
              '4. Jūsų asmeniniai duomenys ir dokumentų kopijos bus ištrinti.',
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 24),
            _buildSection('Kokie duomenys bus ištrinti?', 
              '• Profilio nuotrauka ir asmeniniai duomenys.\n'
              '• Dokumentų kopijos (ID, Draudimas, Technikinė).\n'
              '• Automobilio informacija.\n'
              '• Prieiga prie programėlės.'
            ),
            _buildSection('Teisinės prievolės', 
              'Pagal galiojančius teisės aktus, finansiniai įrašai (pajamos, komisiniai mokesčiai) gali būti saugomi apskaitos tikslais 10 metų.'
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isRequesting ? null : _showConfirmDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isRequesting 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('TEIKTI PRAŠYMĄ IŠTRINTI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(content, style: const TextStyle(fontSize: 15, height: 1.5)),
        const SizedBox(height: 24),
      ],
    );
  }
}
