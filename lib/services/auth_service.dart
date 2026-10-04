import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'app_mode.dart';
import 'demo_store.dart';

/// Who is signed in.
class Session {
  final String uid, phone;
  const Session(this.uid, this.phone);
}

/// Phone-number login with an SMS code (works on Android and iOS).
/// In preview mode any number works with the code 123456.
class AuthService {
  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static const previewCode = '123456';
  static Session? _preview;
  static final _previewChanges = StreamController<void>.broadcast();

  static Stream<Session?> get changes {
    if (AppMode.preview) {
      return Stream<Session?>.multi((c) {
        c.add(_preview);
        final sub = _previewChanges.stream.listen((_) => c.add(_preview));
        c.onCancel = sub.cancel;
      });
    }
    return _auth.authStateChanges().map((u) => u == null ? null : Session(u.uid, u.phoneNumber ?? ''));
  }

  /// Turns "0712 345 678" into "+255712345678".
  static String normalize(String input) {
    var d = input.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('0')) d = '255${d.substring(1)}';
    if (!d.startsWith('255')) d = '255$d';
    return '+$d';
  }

  static bool isValidTz(String input) =>
      RegExp(r'^\+255[67]\d{8}$').hasMatch(normalize(input));

  /// Sends the SMS. [onCode] gets a verificationId to pass to [confirm].
  static Future<void> sendCode(
    String phone, {
    required void Function(String verificationId) onCode,
    required void Function(String message) onError,
    required void Function() onAutoSignIn,
  }) async {
    if (AppMode.preview) {
      await Future.delayed(const Duration(milliseconds: 600));
      onCode(normalize(phone));
      return;
    }
    return _auth.verifyPhoneNumber(
      phoneNumber: normalize(phone),
      timeout: const Duration(seconds: 60),
      verificationCompleted: (cred) async {
        // Android can read the SMS automatically.
        await _auth.signInWithCredential(cred);
        onAutoSignIn();
      },
      verificationFailed: (e) => onError(_message(e)),
      codeSent: (id, _) => onCode(id),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  static Future<void> confirm(String verificationId, String smsCode) async {
    if (AppMode.preview) {
      if (smsCode != previewCode) throw StateError('wrong code');
      final phone = verificationId; // in preview the "verification id" is the phone number
      _preview = Session('preview-${phone.replaceAll('+', '')}', phone);
      DemoStore.currentUid = _preview!.uid;
      _previewChanges.add(null);
      return;
    }
    final cred = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: smsCode);
    await _auth.signInWithCredential(cred);
  }

  static Future<void> signOut() async {
    if (AppMode.preview) {
      _preview = null;
      DemoStore.currentUid = null;
      _previewChanges.add(null);
      return;
    }
    await _auth.signOut();
  }

  static String _message(FirebaseAuthException e) => switch (e.code) {
        'invalid-phone-number' => 'That phone number is not valid. Use the format 0712 345 678.',
        'too-many-requests' => 'Too many attempts. Wait a few minutes and try again.',
        'invalid-verification-code' => 'That code is wrong. Check the SMS and try again.',
        _ => e.message ?? 'Sign in failed. Check your connection and try again.',
      };
}
