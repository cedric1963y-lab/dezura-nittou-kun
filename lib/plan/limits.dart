/// Free tier and the App Store subscription products.
/// Prices are set in App Store Connect. The labels are the Japan fallbacks.
abstract final class PlanLimits {
  static const freeWorkerLimit = 2;
  static const freeSiteLimit = 1;

  static const monthlyProductId = 'jp.dezura.app.premium.monthly';
  static const yearlyProductId = 'jp.dezura.app.premium.yearly';
  static const subscriptionGroupName = '出面・日当くん Premium';
  static const monthlyPriceYen = 300;
  static const yearlyPriceYen = 3000;
  static const monthlyPriceLabel = '¥300';
  static const yearlyPriceLabel = '¥3,000';
  static const bundleId = 'jp.dezura.app';

  /// Introductory offer set in App Store Connect for both products.
  static const freeTrialLabel = '1週間';

  /// Shown on the paywall when the App Store sends no products.
  static const productsUnavailableMessage =
      '価格を読み込めませんでした。通信状況を確認してもう一度開いてください。';

  static const premiumProductIds = {monthlyProductId, yearlyProductId};

  static bool isPremiumProduct(String productId) {
    return premiumProductIds.contains(productId);
  }

  static String priceLabelFor(String productId) {
    if (productId == yearlyProductId) return yearlyPriceLabel;
    return monthlyPriceLabel;
  }

  static String planName(String? productId) {
    if (productId == yearlyProductId) return '年額';
    if (productId == monthlyProductId) return '月額';
    return 'プレミアム';
  }

  /// Used only when StoreKit does not send an expiration date.
  static DateTime periodEnd(String productId, DateTime purchasedAt) {
    final local = purchasedAt.toLocal();
    final months = productId == yearlyProductId ? 12 : 1;
    // Jan 31 + 1 month is the last day of February, not Mar 3.
    final lastDay = DateTime(local.year, local.month + months + 1, 0).day;
    return DateTime(
      local.year,
      local.month + months,
      local.day > lastDay ? lastDay : local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  static bool canAddWorker({required bool premium, required int workerCount}) {
    return premium || workerCount < freeWorkerLimit;
  }

  static bool canAddSite({required bool premium, required int siteCount}) {
    return premium || siteCount < freeSiteLimit;
  }

  /// Free plan sees only the current month. Premium sees every month.
  static bool canOpenMonth({
    required bool premium,
    required DateTime month,
    required DateTime now,
  }) {
    if (premium) return true;
    return month.year == now.year && month.month == now.month;
  }
}

abstract final class AppInfo {
  static const name = '出面・日当くん';
  static const version = '1.0.10';
  static const tagline = '出面をタップで付けて、日当を月末に集計。';
}

abstract final class AppLinks {
  static const base = 'https://cedric1963y-lab.github.io/dezura-nittou-kun/';
  static const support = base;
  static const privacy = '${base}privacy.html';
  static const terms = '${base}terms.html';

  /// Apple standard Terms of Use (EULA).
  static const appleEula =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
  static const manageSubscriptions =
      'https://apps.apple.com/account/subscriptions';
}
