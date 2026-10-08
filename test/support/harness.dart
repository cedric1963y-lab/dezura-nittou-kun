import 'dart:io';

import 'package:dezura_nittou/data/repository.dart';
import 'package:dezura_nittou/plan/entitlement.dart';
import 'package:dezura_nittou/plan/limits.dart';
import 'package:dezura_nittou/services/purchase_gateway.dart';
import 'package:dezura_nittou/state/app_controller.dart';
import 'package:flutter/services.dart';

import 'fake_purchase_gateway.dart';

Future<ByteData> loadTestFont() async {
  final bytes = await File('assets/fonts/NotoSansJP-Regular.ttf').readAsBytes();
  return ByteData.sublistView(bytes);
}

/// Fixed clock: Thursday 8 October 2026, 09:00.
DateTime testNow() => DateTime(2026, 10, 8, 9);

Future<AppController> openController(
  Directory directory, {
  bool premium = false,
  PurchaseGateway? purchases,
  DateTime Function()? now,
}) async {
  final repository = Repository(directory);
  await repository.init();
  final clock = now ?? testNow;
  if (premium) {
    await repository.saveEntitlement(
      Entitlement(
        productId: PlanLimits.monthlyProductId,
        expiresAt: clock().add(const Duration(days: 30)),
      ),
    );
  }
  final controller = AppController(
    repository: repository,
    purchases: purchases ?? FakePurchaseGateway(),
    loadFont: loadTestFont,
    now: clock,
  );
  await controller.load();
  return controller;
}
