enum BedAction { idle, raising, lowering }

class BedModel {
  final BedAction action;
  final double distance;

  BedModel({required this.action, required this.distance});

  factory BedModel.fromJson(Map<String, dynamic> json) {
    return BedModel(
      action: _actionFromString(json['status'] as String? ?? 'idle'),
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static BedAction _actionFromString(String value) {
    if (value.contains('moving_up')) return BedAction.raising;
    if (value.contains('moving_down')) return BedAction.lowering;
    return BedAction.idle;
  }

  BedModel copyWith({BedAction? action, double? distance}) {
    return BedModel(
      action: action ?? this.action,
      distance: distance ?? this.distance,
    );
  }
}
