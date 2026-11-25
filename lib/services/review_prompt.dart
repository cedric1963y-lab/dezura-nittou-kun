import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../plan/limits.dart';

/// Rules for when the official App Store review prompt may be shown.
///
/// The prompt itself is Apple's [SKStoreReviewController] (no custom UI,
/// no incentives). These checks live in Dart so they can be unit-tested.
class ReviewEligibility {
  ReviewEligibility._();

  static const minDistinctUsageDays = 3;
  static const minSuccesses = 1;
  static const minDaysBetweenPrompts = 90;

  static bool shouldRequest({
    required DateTime now,
    required String version,
    required bool paywallVisible,
    required Iterable<String> usageDays,
    required int successCount,
    required DateTime? lastPromptAt,
    required String? lastPromptVersion,
  }) {
    if (paywallVisible) return false;
    final days = usageDays.toSet();
    if (days.length < minDistinctUsageDays) return false;
    if (successCount < minSuccesses) return false;
    if (lastPromptVersion != null && lastPromptVersion == version) {
      return false;
    }
    if (lastPromptAt != null) {
      final today = DateTime(now.year, now.month, now.day);
      final last = DateTime(
        lastPromptAt.year,
        lastPromptAt.month,
        lastPromptAt.day,
      );
      if (today.difference(last).inDays < minDaysBetweenPrompts) {
        return false;
      }
    }
    return true;
  }

  static String dayKey(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// Persistent counters used by [ReviewPrompt].
class ReviewPromptState {
  ReviewPromptState({
    Set<String>? usageDays,
    this.successCount = 0,
    this.lastPromptAt,
    this.lastPromptVersion,
  }) : usageDays = {...?usageDays};

  final Set<String> usageDays;
  int successCount;
  DateTime? lastPromptAt;
  String? lastPromptVersion;

  void recordUsage(DateTime now) {
    usageDays.add(ReviewEligibility.dayKey(now));
  }

  void recordSuccess() {
    successCount += 1;
  }

  void recordPrompt({required DateTime now, required String version}) {
    lastPromptAt = now;
    lastPromptVersion = version;
  }

  Map<String, Object?> toJson() => {
    'usageDays': usageDays.toList()..sort(),
    'successCount': successCount,
    'lastPromptAt': lastPromptAt?.toIso8601String(),
    'lastPromptVersion': lastPromptVersion,
  };

  static ReviewPromptState fromJson(Map<String, dynamic> json) {
    final rawDays = json['usageDays'];
    final days = <String>{};
    if (rawDays is Iterable) {
      for (final item in rawDays) {
        if (item is String && item.isNotEmpty) days.add(item);
      }
    }
    DateTime? lastAt;
    final rawAt = json['lastPromptAt'];
    if (rawAt is String && rawAt.isNotEmpty) {
      lastAt = DateTime.tryParse(rawAt);
    }
    final rawCount = json['successCount'];
    return ReviewPromptState(
      usageDays: days,
      successCount: rawCount is int ? rawCount : 0,
      lastPromptAt: lastAt,
      lastPromptVersion: json['lastPromptVersion'] as String?,
    );
  }
}

/// Asks iOS for the standard App Store rating prompt after a month-end
/// success (viewing 集計 with a 日当合計, or sharing / exporting that month),
/// only when [ReviewEligibility] allows it.
class ReviewPrompt {
  ReviewPrompt._();

  static const _channel = MethodChannel('jp.dezura.app/review');
  static const _screenshot = bool.fromEnvironment('SCREENSHOT');
  static const _fileName = 'review_prompt.json';

  static Directory? _directory;
  static DateTime Function() _clock = DateTime.now;
  static String _version = AppInfo.version;
  static Future<bool> Function() _requester = _requestNative;
  static ReviewPromptState _state = ReviewPromptState();
  static int _paywallDepth = 0;
  static bool _busy = false;

  /// Wire persistence and optional fakes. Safe to call more than once.
  static void attach({
    required Directory directory,
    DateTime Function()? clock,
    String? version,
    Future<bool> Function()? requester,
    ReviewPromptState? state,
  }) {
    _directory = directory;
    if (clock != null) _clock = clock;
    if (version != null) _version = version;
    if (requester != null) _requester = requester;
    _state = state ?? _load();
  }

  /// Test helper: drop stored state and fakes.
  static void resetForTest() {
    _directory = null;
    _clock = DateTime.now;
    _version = AppInfo.version;
    _requester = _requestNative;
    _state = ReviewPromptState();
    _paywallDepth = 0;
    _busy = false;
  }

  static bool get paywallVisible => _paywallDepth > 0;

  static void enterPaywall() => _paywallDepth += 1;

  static void leavePaywall() {
    if (_paywallDepth > 0) _paywallDepth -= 1;
  }

  static ReviewPromptState get debugState => _state;

  static void recordUsage() {
    _state.recordUsage(_clock());
    _save();
  }

  /// The 集計 tab was opened and the current month already has 出面.
  static void afterSummaryViewed({required bool hasEntries}) {
    if (hasEntries) onMonthEndSuccess();
  }

  /// Month-end total was viewed, or a 集計 text / PDF / CSV share finished.
  static void onMonthEndSuccess() {
    _state.recordSuccess();
    _save();
    _maybeAsk();
  }

  static bool get isEligible {
    return ReviewEligibility.shouldRequest(
      now: _clock(),
      version: _version,
      paywallVisible: paywallVisible,
      usageDays: _state.usageDays,
      successCount: _state.successCount,
      lastPromptAt: _state.lastPromptAt,
      lastPromptVersion: _state.lastPromptVersion,
    );
  }

  static Future<void> _maybeAsk() async {
    if (_busy || (kDebugMode && _screenshot) || !isEligible) return;
    _busy = true;
    try {
      // Let the screen settle first so the system sheet doesn't cover the tap.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!isEligible) return;
      final shown = await _requester();
      if (shown) {
        _state.recordPrompt(now: _clock(), version: _version);
        _save();
      }
    } catch (_) {
      // Rating prompt is optional; never disturb the app.
    } finally {
      _busy = false;
    }
  }

  static Future<bool> _requestNative() async {
    final result = await _channel.invokeMethod<bool>('maybeRequestReview');
    return result ?? false;
  }

  static File? get _file {
    final dir = _directory;
    if (dir == null) return null;
    return File('${dir.path}/$_fileName');
  }

  static ReviewPromptState _load() {
    final file = _file;
    if (file == null || !file.existsSync()) return ReviewPromptState();
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is Map<String, dynamic>) {
        return ReviewPromptState.fromJson(json);
      }
      if (json is Map) {
        return ReviewPromptState.fromJson(
          json.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      // Start fresh if the file is unreadable.
    }
    return ReviewPromptState();
  }

  static void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(_state.toJson()));
    } catch (_) {
      // Persistence failure must not break 集計.
    }
  }
}
