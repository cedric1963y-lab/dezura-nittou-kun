import 'dart:convert';
import 'dart:io';

import 'package:dezura_nittou/services/review_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late DateTime now;
  late int requests;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dezura_review_');
    now = DateTime(2026, 11, 26, 10, 0);
    requests = 0;
    ReviewPrompt.resetForTest();
    ReviewPrompt.attach(
      directory: directory,
      clock: () => now,
      version: '1.0.11',
      requester: () async {
        requests += 1;
        return true;
      },
    );
  });

  tearDown(() async {
    ReviewPrompt.resetForTest();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 1300));

  void useDays(int count, {int success = 0}) {
    for (var i = 0; i < count; i++) {
      now = DateTime(2026, 11, 1 + i, 9);
      ReviewPrompt.recordUsage();
    }
    now = DateTime(2026, 11, 1 + count - 1, 15);
    for (var i = 0; i < success; i++) {
      ReviewPrompt.onMonthEndSuccess();
    }
  }

  test('first launch never prompts, even after a month-end success', () async {
    ReviewPrompt.recordUsage();
    ReviewPrompt.onMonthEndSuccess();
    await settle();
    expect(requests, 0);
    expect(ReviewPrompt.debugState.usageDays, {'2026-11-26'});
    expect(ReviewPrompt.debugState.successCount, 1);
  });

  test('two distinct days and a success are not enough', () async {
    useDays(2, success: 1);
    await settle();
    expect(ReviewPrompt.debugState.usageDays.length, 2);
    expect(requests, 0);
  });

  test('three days without a month-end success never prompt', () async {
    useDays(3, success: 0);
    await settle();
    expect(ReviewPrompt.debugState.usageDays.length, 3);
    expect(ReviewPrompt.debugState.successCount, 0);
    expect(requests, 0);
  });

  test('three days and one success may prompt once', () async {
    useDays(3, success: 1);
    await settle();
    expect(requests, 1);
    expect(ReviewPrompt.debugState.lastPromptVersion, '1.0.11');
    expect(ReviewPrompt.debugState.lastPromptAt, now);
  });

  test('same calendar day is counted only once', () {
    ReviewPrompt.recordUsage();
    now = DateTime(2026, 11, 26, 21, 30);
    ReviewPrompt.recordUsage();
    expect(ReviewPrompt.debugState.usageDays, {'2026-11-26'});
  });

  test('same version does not prompt again', () async {
    useDays(3, success: 1);
    await settle();
    expect(requests, 1);
    now = DateTime(2026, 12, 10, 10);
    ReviewPrompt.recordUsage();
    ReviewPrompt.onMonthEndSuccess();
    await settle();
    expect(requests, 1);
  });

  test('new version still waits about 90 days', () async {
    useDays(3, success: 1);
    await settle();
    expect(requests, 1);

    ReviewPrompt.resetForTest();
    now = DateTime(2026, 11, 3).add(const Duration(days: 89));
    ReviewPrompt.attach(
      directory: directory,
      clock: () => now,
      version: '1.0.12',
      requester: () async {
        requests += 1;
        return true;
      },
    );
    ReviewPrompt.recordUsage();
    ReviewPrompt.onMonthEndSuccess();
    await settle();
    expect(requests, 1);
  });

  test('new version may prompt again after 90 days', () async {
    useDays(3, success: 1);
    await settle();
    expect(requests, 1);

    ReviewPrompt.resetForTest();
    now = DateTime(2026, 11, 3).add(const Duration(days: 90));
    ReviewPrompt.attach(
      directory: directory,
      clock: () => now,
      version: '1.0.12',
      requester: () async {
        requests += 1;
        return true;
      },
    );
    ReviewPrompt.recordUsage();
    ReviewPrompt.onMonthEndSuccess();
    await settle();
    expect(requests, 2);
    expect(ReviewPrompt.debugState.lastPromptVersion, '1.0.12');
  });

  test('never prompts while the paywall is open', () async {
    useDays(3, success: 0);
    await settle();
    ReviewPrompt.enterPaywall();
    ReviewPrompt.onMonthEndSuccess();
    await settle();
    expect(requests, 0);
    ReviewPrompt.leavePaywall();
    ReviewPrompt.onMonthEndSuccess();
    await settle();
    expect(requests, 1);
  });

  test('failed native request is not recorded, so it can retry', () async {
    var allow = false;
    ReviewPrompt.resetForTest();
    now = DateTime(2026, 11, 3, 15);
    ReviewPrompt.attach(
      directory: directory,
      clock: () => now,
      version: '1.0.11',
      requester: () async {
        requests += 1;
        return allow;
      },
    );
    useDays(3, success: 1);
    await settle();
    expect(requests, 1);
    expect(ReviewPrompt.debugState.lastPromptVersion, isNull);

    allow = true;
    ReviewPrompt.onMonthEndSuccess();
    await settle();
    expect(requests, 2);
    expect(ReviewPrompt.debugState.lastPromptVersion, '1.0.11');
  });

  test('state is persisted across attach', () async {
    useDays(3, success: 1);
    await settle();
    expect(requests, 1);
    final path = File('${directory.path}/review_prompt.json');
    expect(path.existsSync(), isTrue);
    final saved = jsonDecode(path.readAsStringSync()) as Map<String, dynamic>;
    expect(saved['successCount'], greaterThanOrEqualTo(1));
    expect(saved['lastPromptVersion'], '1.0.11');

    ReviewPrompt.resetForTest();
    requests = 0;
    now = DateTime(2026, 11, 20);
    ReviewPrompt.attach(
      directory: directory,
      clock: () => now,
      version: '1.0.11',
      requester: () async {
        requests += 1;
        return true;
      },
    );
    expect(ReviewPrompt.debugState.usageDays.length, 3);
    expect(ReviewPrompt.debugState.lastPromptVersion, '1.0.11');
    ReviewPrompt.onMonthEndSuccess();
    await settle();
    expect(requests, 0);
  });

  test('eligibility unit: paywall, first days, and 90-day math', () {
    expect(
      ReviewEligibility.shouldRequest(
        now: DateTime(2026, 11, 26),
        version: '1.0.11',
        paywallVisible: false,
        usageDays: const ['2026-11-24', '2026-11-25', '2026-11-26'],
        successCount: 1,
        lastPromptAt: null,
        lastPromptVersion: null,
      ),
      isTrue,
    );
    expect(
      ReviewEligibility.shouldRequest(
        now: DateTime(2026, 11, 26),
        version: '1.0.11',
        paywallVisible: true,
        usageDays: const ['2026-11-24', '2026-11-25', '2026-11-26'],
        successCount: 1,
        lastPromptAt: null,
        lastPromptVersion: null,
      ),
      isFalse,
    );
    expect(
      ReviewEligibility.shouldRequest(
        now: DateTime(2026, 11, 26),
        version: '1.0.11',
        paywallVisible: false,
        usageDays: const ['2026-11-26'],
        successCount: 1,
        lastPromptAt: null,
        lastPromptVersion: null,
      ),
      isFalse,
    );
    expect(
      ReviewEligibility.shouldRequest(
        now: DateTime(2026, 2, 26),
        version: '1.0.12',
        paywallVisible: false,
        usageDays: const ['2026-02-24', '2026-02-25', '2026-02-26'],
        successCount: 2,
        lastPromptAt: DateTime(2025, 11, 29),
        lastPromptVersion: '1.0.11',
      ),
      isFalse,
    );
    expect(
      ReviewEligibility.shouldRequest(
        now: DateTime(2026, 2, 27),
        version: '1.0.12',
        paywallVisible: false,
        usageDays: const ['2026-02-25', '2026-02-26', '2026-02-27'],
        successCount: 2,
        lastPromptAt: DateTime(2025, 11, 29),
        lastPromptVersion: '1.0.11',
      ),
      isTrue,
    );
  });
}
