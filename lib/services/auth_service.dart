import 'package:firebase_auth/firebase_auth.dart';

/// Phone-number login with an SMS code (works on Android and iOS).
class AuthService {
  static final _auth = FirebaseAuth.instance;

  static Stream<User?> get changes => _auth.authStateChanges();
  static User? get current => _auth.currentUser;

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
  }) {
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
    final cred = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: smsCode);
    await _auth.signInWithCredential(cred);
  }

  static Future<void> signOut() => _auth.signOut();

  static String _message(FirebaseAuthException e) => switch (e.code) {
        'invalid-phone-number' => 'That phone number is not valid. Use the format 0712 345 678.',
        'too-many-requests' => 'Too many attempts. Wait a few minutes and try again.',
        'invalid-verification-code' => 'That code is wrong. Check the SMS and try again.',
        _ => e.message ?? 'Sign in failed. Check your connection and try again.',
      };
}
