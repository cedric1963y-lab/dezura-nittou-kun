/// A day's work plan (明日の予定). Stored apart from 出面 records and
/// never used in 集計, PDF or CSV.
class SitePlan {
  const SitePlan({
    required this.siteId,
    this.workerIds = const [],
    this.note = '',
  });

  final String siteId;

  /// Workers assigned to this site, in roster order.
  final List<String> workerIds;

  /// Short memo such as 集合8時. Empty when unused.
  final String note;

  bool get isEmpty => workerIds.isEmpty && note.trim().isEmpty;

  SitePlan copyWith({List<String>? workerIds, String? note}) {
    return SitePlan(
      siteId: siteId,
      workerIds: workerIds ?? this.workerIds,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
    'siteId': siteId,
    'workerIds': workerIds,
    'note': note,
  };

  static SitePlan fromJson(Map<String, dynamic> json) {
    final raw = json['workerIds'];
    return SitePlan(
      siteId: (json['siteId'] as String?) ?? '',
      workerIds: [
        if (raw is List)
          for (final id in raw)
            if (id is String && id.isNotEmpty) id,
      ],
      note: (json['note'] as String?) ?? '',
    );
  }
}

class DayPlan {
  const DayPlan({required this.day, this.sites = const []});

  /// `YYYY-MM-DD`, same as [dayKey].
  final String day;
  final List<SitePlan> sites;

  bool get isEmpty => sites.every((s) => s.isEmpty);

  SitePlan site(String siteId) {
    for (final s in sites) {
      if (s.siteId == siteId) return s;
    }
    return SitePlan(siteId: siteId);
  }

  DayPlan copyWith({List<SitePlan>? sites}) =>
      DayPlan(day: day, sites: sites ?? this.sites);

  Map<String, dynamic> toJson() => {
    'day': day,
    'sites': [
      for (final s in sites)
        if (!s.isEmpty) s.toJson(),
    ],
  };

  static DayPlan fromJson(Map<String, dynamic> json) {
    final raw = json['sites'];
    return DayPlan(
      day: (json['day'] as String?) ?? '',
      sites: [
        if (raw is List)
          for (final item in raw)
            if (item is Map<String, dynamic>)
              SitePlan.fromJson(item)
            else if (item is Map)
              SitePlan.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }
}

/// Longest optional memo on a site plan.
const maxPlanNoteLength = 30;

/// Plans older than this many days (and farther ahead than this) are dropped.
const planRetentionDays = 14;
