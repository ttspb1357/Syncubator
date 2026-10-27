/// Priority tiers mirror the backend's ALARM_SPECS and drive both the
/// banner colour and the buzzer cadence on the Pi. Ordering follows the
/// spirit of IEC 60601-1-8: high = red, medium = amber, low = cyan.
enum AlarmPriority { high, medium, low }

AlarmPriority _priorityFromString(String? value) {
  switch (value) {
    case 'high':
      return AlarmPriority.high;
    case 'medium':
      return AlarmPriority.medium;
    default:
      // Unknown priorities degrade to `low` rather than throwing — a
      // backend that gains a new tier must never crash an older client
      // that is displaying safety information.
      return AlarmPriority.low;
  }
}

/// A single raised alarm, as reported by the Pi.
///
/// Note [active] and [acknowledged] are independent: an alarm whose
/// condition has cleared but which was never acknowledged stays in the
/// list with `active == false` (latched), so a transient event is still
/// visible to whoever wasn't watching the screen when it happened.
class AlarmItem {
  final String id;
  final AlarmPriority priority;
  final String label;

  /// The reading that tripped the alarm. Numeric for threshold alarms
  /// (temperature, humidity, O2) but a status string for sensor-fault
  /// alarms, so this is deliberately untyped — use [formattedValue].
  final dynamic value;

  final bool active;
  final bool acknowledged;
  final DateTime? since;

  AlarmItem({
    required this.id,
    required this.priority,
    required this.label,
    required this.value,
    required this.active,
    required this.acknowledged,
    required this.since,
  });

  factory AlarmItem.fromJson(Map<String, dynamic> json) {
    final rawSince = json['since'] as num?;
    return AlarmItem(
      id: json['id'] as String? ?? '',
      priority: _priorityFromString(json['priority'] as String?),
      label: json['label'] as String? ?? 'Unknown alarm',
      value: json['value'],
      active: json['active'] as bool? ?? false,
      acknowledged: json['acknowledged'] as bool? ?? false,
      // Backend sends a Unix timestamp in seconds (time.time()).
      since: rawSince == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((rawSince * 1000).round()),
    );
  }

  String get formattedValue {
    final v = value;
    if (v == null) return '--';
    if (v is num) return v.toStringAsFixed(1);
    return v.toString();
  }

  /// How long this alarm has been raised, in a form suitable for a
  /// bedside glance rather than precise timing.
  String get ageLabel {
    final start = since;
    if (start == null) return '';
    final elapsed = DateTime.now().difference(start);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) {
      return '${elapsed.inHours}h ${elapsed.inMinutes % 60}m ago';
    }
    return '${elapsed.inDays}d ago';
  }
}

class AlarmsModel {
  final List<AlarmItem> items;

  /// Highest priority among everything currently displayed, including
  /// silenced and cleared-but-latched alarms — this drives the banner.
  final AlarmPriority? highestPriority;

  /// Whether the Pi's buzzer is currently sounding. False once every
  /// active alarm has been acknowledged, even though they remain listed.
  final bool sounding;

  /// Highest priority among only the alarms actually sounding, which can
  /// be lower than [highestPriority] when the top alarm is silenced.
  final AlarmPriority? soundingPriority;

  /// SOS raised by hand from a screen. Separate from [items]: it is not a
  /// condition the Pi evaluates, it stays on until someone cancels it, and
  /// acknowledging alarms does not silence it.
  final bool sosActive;
  final DateTime? sosSince;

  /// Which kind of screen raised the SOS: "kiosk", "phone" or "web".
  final String? sosFrom;

  AlarmsModel({
    required this.items,
    required this.highestPriority,
    required this.sounding,
    required this.soundingPriority,
    this.sosActive = false,
    this.sosSince,
    this.sosFrom,
  });

  /// [sos] is the `/status` payload's top-level `sos` object, which sits
  /// beside `alarms` rather than inside it.
  factory AlarmsModel.fromJson(Map<String, dynamic> json,
      {Map<String, dynamic>? sos}) {
    final rawItems = json['items'] as List? ?? const [];
    final rawSosSince = sos?['since'] as num?;
    return AlarmsModel(
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(AlarmItem.fromJson)
          .toList(),
      highestPriority: json['highest_priority'] == null
          ? null
          : _priorityFromString(json['highest_priority'] as String?),
      sounding: json['sounding'] as bool? ?? false,
      soundingPriority: json['sounding_priority'] == null
          ? null
          : _priorityFromString(json['sounding_priority'] as String?),
      sosActive: sos?['active'] as bool? ?? false,
      sosSince: rawSosSince == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((rawSosSince * 1000).round()),
      sosFrom: sos?['raised_from'] as String?,
    );
  }

  factory AlarmsModel.empty({bool sosActive = false, DateTime? sosSince, String? sosFrom}) =>
      AlarmsModel(
        items: const [],
        highestPriority: null,
        sounding: false,
        soundingPriority: null,
        sosActive: sosActive,
        sosSince: sosSince,
        sosFrom: sosFrom,
      );

  bool get isEmpty => items.isEmpty;
  int get unacknowledgedCount =>
      items.where((i) => i.active && !i.acknowledged).length;
}
