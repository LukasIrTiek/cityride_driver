import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class InvoiceService {
  static const String _siteProKey = 'cd2e29b70f6c719b7523cc569b4b8878f2b3eabf13b199f52a7a29c0254ce416';
  static const String _siteProPassword = '71ee0e74d1aa88c53021df4804a026043a68e05ad4a410b2f1e4abd7c6f658a2';

  static String _removeAccents(String text) {
    var str = text;
    var map = {
      'ą': 'a', 'Ą': 'A',
      'č': 'c', 'Č': 'C',
      'ę': 'e', 'Ę': 'E',
      'ė': 'e', 'Ė': 'E',
      'į': 'i', 'Į': 'I',
      'š': 's', 'Š': 'S',
      'ų': 'u', 'Ų': 'U',
      'ū': 'u', 'Ū': 'U',
      'ž': 'z', 'Ž': 'Z',
    };
    map.forEach((key, value) {
      str = str.replaceAll(key, value);
    });
    return str;
  }

  static Future<void> generateMonthlyCommissionReport({
    required List<dynamic> earnings,
    required String month,
    required String driverName,
    String? ivNumber,
  }) async {
    final pdf = pw.Document();
    double totalCommission = 0;
    double totalFare = 0;
    
    final cleanDriverName = _removeAccents(driverName);
    final cleanMonth = _removeAccents(month);
    final cleanIvNumber = ivNumber != null ? _removeAccents(ivNumber) : '';
    
    final String invoiceNumber = 'CR-${DateFormat('yyyyMM').format(DateTime.now())}-${cleanDriverName.split(' ').first.toUpperCase()}';
    final String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    for (var entry in earnings) {
      totalCommission += double.tryParse(entry['commission'].toString()) ?? 0;
      totalFare += double.tryParse(entry['total_fare'].toString()) ?? 0;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_removeAccents('SASKAITA FAKTURA'), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Serija CR Nr. $invoiceNumber'),
                    pw.Text('Data: $dateStr'),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('CityRide Platform', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('MB cityride'),
                    pw.Text(_removeAccents('Vadovas Lukas Petkevicius')),
                    pw.Text(_removeAccents('Laisves al. 85E-5, LT-44297 Kaunas')),
                    pw.Text(_removeAccents('Im. kodas: 307727101')),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(_removeAccents('PIRKEJAS (VAIRUOTOJAS):'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(cleanDriverName),
            if (cleanIvNumber.isNotEmpty) pw.Text('IV veiklos nr.: $cleanIvNumber'),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: [_removeAccents('Data'), _removeAccents('Paslauga'), _removeAccents('Apyvarta'), _removeAccents('Komisinis (10%)')],
              data: earnings.map((e) {
                final type = e['type'] == 'cancellation_fee' ? 'Atsaukimas' : 'Kelione';
                return [
                  DateFormat('MM-dd').format(DateTime.parse(e['created_at']).toLocal()),
                  type,
                  '${(double.tryParse(e['total_fare'].toString()) ?? 0).toStringAsFixed(2)} EUR',
                  '${(double.tryParse(e['commission'].toString()) ?? 0).toStringAsFixed(2)} EUR',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 30),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(_removeAccents('Is viso apyvarta: ${(totalFare).toStringAsFixed(2)} EUR')),
                    pw.Text('PVM (0%): 0.00 EUR'),
                    pw.SizedBox(width: 150, child: pw.Divider()),
                    pw.Text(_removeAccents('MOKETI (KOMISINIS): ${(totalCommission).toStringAsFixed(2)} EUR'),
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 50),
            pw.Text(_removeAccents('Saskaita sugeneruota automatiska CityRide sistemoje.'), style: pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Saskaita_$invoiceNumber.pdf');
  }

  static Future<void> syncCommissionToSitePro({
    required String driverName,
    required String month,
    required double amount,
    String? invoiceNo,
  }) async {
    try {
      final url = Uri.parse('https://site.pro/api/v1/sync');
      final cleanName = _removeAccents(driverName);
      final cleanMonth = _removeAccents(month);
      final number = invoiceNo ?? 'COMM-${DateFormat('yyyyMM').format(DateTime.now())}';
      
      final payload = {
        'key': _siteProKey,
        'password': _siteProPassword,
        'action': 'add-invoice',
        'data': {
          'invoice': {
            'number': number,
            'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
            'client_name': cleanName,
            'description': _removeAccents('Komisiniai uz $cleanMonth ($cleanName)'),
            'amount': amount,
            'currency': 'EUR',
            'vat_rate': 0,
            'status': 'unpaid'
          }
        }
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        print('Site.pro sync success: ${response.body}');
      } else {
        print('Site.pro sync failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Site.pro sync error: $e');
    }
  }
}
