/// Other apps in the same 建設シリーズ, shown in 設定 as 職人の道具箱.
/// Keep 出面・日当くん itself out of the list.
class ConstructionApp {
  const ConstructionApp({
    required this.id,
    required this.name,
    required this.blurb,
  });

  /// App Store numeric id.
  final int id;
  final String name;

  /// One-line description, no prices.
  final String blurb;

  String get storeUrl => 'https://apps.apple.com/jp/app/id$id';
}

abstract final class ConstructionApps {
  static const mitsumori = ConstructionApp(
    id: 6820367399,
    name: 'かんたん見積・請求くん',
    blurb: '工事の見積書・請求書を作る',
  );

  static const koutei = ConstructionApp(
    id: 6836845198, // 工事の工程表
    name: '工事の工程表',
    blurb: '現場の工程を帯で見て、雨の順延もまとめてずらす',
  );

  static const shashinNippo = ConstructionApp(
    id: 6820176592,
    name: '写真日報くん',
    blurb: '写真付きの作業日報を作る',
  );

  static const shokocho = ConstructionApp(
    id: 6819914622,
    name: '仕事の証拠帳',
    blurb: '作業の記録と報告書を残す',
  );

  static const zaiseki = ConstructionApp(
    id: 6816288691,
    name: '現場材積くん',
    blurb: '材積・板材の体積を計算する',
  );

  static const nurimenseki = ConstructionApp(
    id: 6813789213,
    name: '塗り面積くん',
    blurb: '塗料・生コンの面積を計算する',
  );

  /// The other construction apps, 見積 first for the 月末集計 prompt.
  static const others = [
    mitsumori,
    koutei,
    shashinNippo,
    shokocho,
    zaiseki,
    nurimenseki,
  ];
}
