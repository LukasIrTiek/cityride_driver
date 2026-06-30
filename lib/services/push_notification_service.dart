import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  static final supabase = Supabase.instance.client;

  static Future<void> saveDriverToken() async {

    final user =
        supabase.auth.currentUser;

    if (user == null) return;

    final token =
    await FirebaseMessaging.instance.getToken();

    if (token == null) return;

    await supabase
        .from('drivers')
        .update({
      'fcm_token': token,
    })
        .eq('id', user.id);
  }
}