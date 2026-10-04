import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Push notifications: new order for the shop, new job for riders,
/// status changes for the customer. Sent by the Cloud Functions.
class PushService {
  static Future<void> init() async {
    // Notifications are optional: the app keeps working if this fails.
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
    } catch (_) {}
  }

  /// Call after sign-in. Asks permission (iOS shows a dialog) and stores this
  /// phone's token so the server knows where to send notifications.
  static Future<void> registerDevice(String uid) async {
    try {
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await m.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.doc('users/$uid').set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
      // Riders subscribe to the jobs topic when they register (see rider_home.dart).
    } catch (_) {}
  }

  static Future<void> subscribeRiderJobs(bool on) async {
    try {
      on
          ? await FirebaseMessaging.instance.subscribeToTopic('rider-jobs')
          : await FirebaseMessaging.instance.unsubscribeFromTopic('rider-jobs');
    } catch (_) {}
  }
}
