/// Preview mode runs the whole app on the phone with sample data, so it can be
/// installed and tried before a Firebase project is connected. It switches on
/// automatically when `lib/firebase_options.dart` is still the placeholder.
class AppMode {
  static bool preview = false;

  /// An order to open as soon as the customer screen appears (used by the
  /// automatic screenshot check on GitHub; never set in normal use).
  static String? openOrderOnStart;
}
