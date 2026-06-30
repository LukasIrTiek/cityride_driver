import 'package:flutter/material.dart';

class NewsPage extends StatelessWidget {
  const NewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF8F9FA),
      appBar: AppBar(
        title: const Text('Naujienos', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildNewsCard(
            title: 'Sveiki prisijungę!',
            date: 'Šiandien',
            content: '''
Dėkojame, kad prisijungėte prie mūsų vairuotojų bendruomenės!

Prieš pradėdami dirbti, įsitikinkite, kad:
• Užpildėte visą savo profilio informaciją.
• Įkėlėte visus reikiamus dokumentus.
• Gavote administratoriaus patvirtinimą.
• Jūsų automobilio informacija yra teisinga.

Svarbu:
• Užmokestis už atliktas keliones išmokamas vieną kartą per savaitę į jūsų nurodytą banko sąskaitą.
• Visus svarbius platformos atnaujinimus rasite šioje naujienų skiltyje.
• Jei kyla klausimų ar problemų, susisiekite su administracija per pagalbos skiltį.

Linkime saugių kelionių ir sėkmingo darbo!
            ''',
            isNew: true,
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard({required String title, required String date, required String content, bool isNew = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5)),
        ],
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
                  child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                if (isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                    child: const Text('NAUJA', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              content.trim(),
              style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Text(date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
