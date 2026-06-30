import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;

class DocumentService {
  static final _supabase = Supabase.instance.client;
  static const String bucketName = 'driver-documents';

  static Future<List<Map<String, dynamic>>> getDriverDocuments() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];
    
    final response = await _supabase
        .from('driver_documents')
        .select()
        .eq('driver_id', user.id)
        .isFilter('deleted_at', null);
    
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<void> uploadDocument({
    required String type,
    required File file,
    String? docNumber,
    DateTime? issuedAt,
    DateTime? expiryDate,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Vartotojas neprisijungęs');

    final fileExt = p.extension(file.path).toLowerCase();
    final fileName = '${user.id}_${_sanitize(type)}_${DateTime.now().millisecondsSinceEpoch}$fileExt';

    // 1. Upload to Storage
    await _supabase.storage.from(bucketName).upload(
      fileName,
      file,
      fileOptions: const FileOptions(upsert: true),
    );

    final fileUrl = _supabase.storage.from(bucketName).getPublicUrl(fileName);

    // 2. Save to Database
    await _supabase.from('driver_documents').upsert({
      'driver_id': user.id,
      'document_type': type,
      'document_number': docNumber,
      'issued_at': issuedAt?.toIso8601String(),
      'expiry_date': expiryDate?.toIso8601String(),
      'status': 'pending',
      'file_url': fileUrl,
      'updated_at': DateTime.now().toIso8601String(),
      'admin_comment': null,
    }, onConflict: 'driver_id, document_type');
  }

  static Future<void> deleteDocument(String docId) async {
    await _supabase.from('driver_documents').update({
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', docId);
  }

  static String _sanitize(String text) {
    return text.toLowerCase()
        .replaceAll('ą', 'a').replaceAll('č', 'c').replaceAll('ę', 'e')
        .replaceAll('ė', 'e').replaceAll('į', 'i').replaceAll('š', 's')
        .replaceAll('ų', 'u').replaceAll('ū', 'u').replaceAll('ž', 'z')
        .replaceAll(' ', '_');
  }
}
