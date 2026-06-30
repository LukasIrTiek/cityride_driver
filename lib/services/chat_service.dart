import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  static final _supabase = Supabase.instance.client;

  static Stream<List<Map<String, dynamic>>> getMessagesStream(String rideId) {
    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('ride_id', rideId)
        .order('created_at')
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  static Future<void> sendMessage(String rideId, String content) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // Check 24h limit
    final rideRes = await _supabase.from('rides').select('status, completed_at').eq('id', rideId).single();
    if (rideRes['status'] == 'completed' && rideRes['completed_at'] != null) {
      final completedAt = DateTime.parse(rideRes['completed_at']).toLocal();
      if (DateTime.now().difference(completedAt).inHours >= 24) {
        throw Exception('Pokalbis pasibaigė (praėjo daugiau nei 24 valandos)');
      }
    }

    await _supabase.from('messages').insert({
      'ride_id': rideId,
      'sender_id': user.id,
      'content': content,
    });

    // Notify other party via Edge Function
    await _supabase.functions.invoke('notify-new-message', body: {
      'ride_id': rideId,
      'content': content,
      'sender_name': user.userMetadata?['full_name'] ?? 'Vairuotojas',
    });
  }

  static Future<void> markAsRead(String rideId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _supabase
        .from('messages')
        .update({'is_read': true})
        .eq('ride_id', rideId)
        .neq('sender_id', user.id);
  }

  static Future<List<String>> getQuickMessages(bool isDriver) async {
    final role = isDriver ? 'driver' : 'passenger';
    final res = await _supabase.from('quick_messages').select('content').eq('role', role);
    return List<String>.from(res.map((e) => e['content']));
  }
}
