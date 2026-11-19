import 'dart:typed_data';
import 'dart:ui' as ui;

import '../format.dart';
import '../models/plans.dart';
import '../models/records.dart';

/// One site block on the 予定 image. Never includes money or 日当.
class PlanImageSite {
  const PlanImageSite({
    required this.name,
    required this.address,
    required this.note,
    required this.workers,
  });

  final String name;
  final String address;
  final String note;
  final List<String> workers;
}

/// Layout model for the share image.
class PlanImageContent {
  const PlanImageContent({
    required this.title,
    this.businessName = '',
    this.sites = const [],
  });

  final String title;
  final String businessName;
  final List<PlanImageSite> sites;

  bool get isEmpty => sites.isEmpty;
}

/// Builds the image model from a saved plan. Unknown ids and empty
/// sites are dropped. Nothing about pay is included.
PlanImageContent planImageContent({
  required DayPlan plan,
  required DateTime day,
  required List<Site> sites,
  required List<Worker> workers,
  String businessName = '',
}) {
  final siteById = {for (final s in sites) s.id: s};
  final workerById = {for (final w in workers) w.id: w};
  final blocks = <PlanImageSite>[];
  for (final entry in plan.sites) {
    final site = siteById[entry.siteId];
    if (site == null) continue;
    final names = [
      for (final id in entry.workerIds)
        if (workerById[id] != null) workerById[id]!.name,
    ];
    final note = entry.note.trim();
    if (names.isEmpty && note.isEmpty) continue;
    blocks.add(
      PlanImageSite(
        name: site.name,
        address: site.address.trim(),
        note: note,
        workers: names,
      ),
    );
  }
  return PlanImageContent(
    title: formatPlanTitle(day),
    businessName: businessName.trim(),
    sites: blocks,
  );
}

const planImageWidth = 1080.0;
const planImageMinHeight = 1600.0;

/// Portrait PNG of [content], readable on a phone. Uses [fontData]
/// (Noto Sans JP) so Japanese glyphs render without a widget tree.
Future<Uint8List> renderPlanPng({
  required PlanImageContent content,
  required ByteData fontData,
  String fontFamily = 'DezuraPlanFont',
}) async {
  await ui.loadFontFromList(
    fontData.buffer.asUint8List(),
    fontFamily: fontFamily,
  );

  const width = planImageWidth;
  const pad = 64.0;
  const inner = width - pad * 2;
  const navy = 0xFF1F3A57;
  const navyDeep = 0xFF152A40;
  const amber = 0xFFF5A300;
  const paper = 0xFFF4F2EC;
  const ink = 0xFF1B1F24;
  const muted = 0xFF5B6470;
  const card = 0xFFFFFFFF;
  const line = 0xFFE2DED4;

  ui.Paragraph para(
    String text, {
    required double size,
    required int color,
    ui.FontWeight weight = ui.FontWeight.w400,
    ui.TextAlign align = ui.TextAlign.left,
    double? height,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        textAlign: align,
        height: height,
        maxLines: 8,
        ellipsis: '…',
      ),
    )..pushStyle(ui.TextStyle(color: ui.Color(color), fontFamily: fontFamily));
    builder.addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: inner));
    return paragraph;
  }

  final title = para(
    content.title,
    size: 54,
    color: 0xFFFFFFFF,
    weight: ui.FontWeight.w700,
  );
  final business = content.businessName.isEmpty
      ? null
      : para(content.businessName, size: 28, color: 0xFFE8EEF4);
  const headerPadTop = 72.0;
  const headerPadBottom = 36.0;
  var headerH = headerPadTop + title.height + headerPadBottom;
  if (business != null) headerH += business.height + 10;

  final siteLayouts = <_SiteLayout>[];
  var bodyH = 0.0;
  for (final site in content.sites) {
    final name = para(
      site.name,
      size: 40,
      color: ink,
      weight: ui.FontWeight.w700,
    );
    final address = site.address.isEmpty
        ? null
        : para(site.address, size: 28, color: muted);
    final note = site.note.isEmpty
        ? null
        : para(site.note, size: 30, color: navy, weight: ui.FontWeight.w600);
    final workers = site.workers.isEmpty
        ? null
        : para(
            [for (final w in site.workers) '・$w'].join('\n'),
            size: 34,
            color: ink,
            weight: ui.FontWeight.w600,
            height: 1.45,
          );
    var h = 36 + name.height;
    if (address != null) h += 10 + address.height;
    if (note != null) h += 12 + note.height;
    if (workers != null) h += 16 + workers.height;
    h += 36;
    siteLayouts.add(
      _SiteLayout(
        height: h,
        name: name,
        address: address,
        note: note,
        workers: workers,
      ),
    );
    bodyH += h + 28;
  }
  if (content.sites.isEmpty) {
    final empty = para('予定はまだありません。', size: 32, color: muted);
    siteLayouts.add(_SiteLayout(height: 36 + empty.height + 36, name: empty));
    bodyH += 36 + empty.height + 36 + 28;
  }

  final footer = para(
    '出面・日当くんで作成',
    size: 22,
    color: muted,
    align: ui.TextAlign.center,
  );
  const footerGap = 20.0;
  final height = [
    headerH + 8 + 36 + bodyH + footerGap + footer.height + 48,
    planImageMinHeight,
  ].reduce((a, b) => a > b ? a : b);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final rect = ui.Rect.fromLTWH(0, 0, width, height);
  canvas.drawRect(rect, ui.Paint()..color = ui.Color(paper));

  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width, headerH),
    ui.Paint()..color = ui.Color(navyDeep),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, 16, headerH),
    ui.Paint()..color = ui.Color(amber),
  );
  var y = headerPadTop;
  canvas.drawParagraph(title, ui.Offset(pad, y));
  y += title.height;
  if (business != null) {
    y += 10;
    canvas.drawParagraph(business, ui.Offset(pad, y));
    y += business.height;
  }
  canvas.drawRect(
    ui.Rect.fromLTWH(0, headerH, width, 8),
    ui.Paint()..color = ui.Color(amber),
  );

  y = headerH + 8 + 36;
  final cardPaint = ui.Paint()..color = ui.Color(card);
  final stroke = ui.Paint()
    ..color = ui.Color(line)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 2;
  for (final block in siteLayouts) {
    final rrect = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(pad, y, inner, block.height),
      const ui.Radius.circular(24),
    );
    canvas.drawRRect(rrect, cardPaint);
    canvas.drawRRect(rrect, stroke);
    var iy = y + 36;
    canvas.drawParagraph(block.name, ui.Offset(pad + 36, iy));
    iy += block.name.height;
    if (block.address != null) {
      iy += 10;
      canvas.drawParagraph(block.address!, ui.Offset(pad + 36, iy));
      iy += block.address!.height;
    }
    if (block.note != null) {
      iy += 12;
      canvas.drawParagraph(block.note!, ui.Offset(pad + 36, iy));
      iy += block.note!.height;
    }
    if (block.workers != null) {
      iy += 16;
      canvas.drawParagraph(block.workers!, ui.Offset(pad + 36, iy));
    }
    y += block.height + 28;
  }

  canvas.drawParagraph(footer, ui.Offset(pad, height - footer.height - 48));

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (bytes == null) {
    throw StateError('予定の画像を作れませんでした。');
  }
  return bytes.buffer.asUint8List();
}

class _SiteLayout {
  const _SiteLayout({
    required this.height,
    required this.name,
    this.address,
    this.note,
    this.workers,
  });

  final double height;
  final ui.Paragraph name;
  final ui.Paragraph? address;
  final ui.Paragraph? note;
  final ui.Paragraph? workers;
}
