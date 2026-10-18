import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asks iOS for the standard App Store rating prompt (SKStoreReviewController)
/// at most once per app version. The native side (AppDelegate.swift) keeps
/// the "already asked for this version" flag in UserDefaults; iOS itself also
/// rate-limits how often the prompt really appears.
///
/// Moments:
/// - the 集計 tab is opened while the current month has 出面
/// - 10 or more 出面 have been recorded in total
class ReviewPrompt {
  ReviewPrompt._();

  static const _channel = MethodChannel('jp.dezura.app/review');
  static const _screenshot = bool.fromEnvironment('SCREENSHOT');
  static const entryThreshold = 10;

  static bool _doneThisRun = false;
  static bool _busy = false;

  static void afterSummaryViewed({required bool hasEntries}) {
    if (hasEntries) _ask();
  }

  static void afterEntry(int totalEntries) {
    if (totalEntries >= entryThreshold) _ask();
  }

  static Future<void> _ask() async {
    if (_doneThisRun || _busy || (kDebugMode && _screenshot)) return;
    _busy = true;
    try {
      // Let the screen settle first so the prompt doesn't cover the tap.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await _channel.invokeMethod<bool>('maybeRequestReview');
      _doneThisRun = true;
    } catch (_) {
      // Rating prompt is optional; never disturb the app.
    } finally {
      _busy = false;
    }
  }
}
