/// Lid actuator state from the Pi's `/status` payload (`lid`).
///
/// The Pi has no lid position sensor: [isOpen] is simply "an Open has been
/// run and no Close has finished since", which is what locks the Open button.
class LidModel {
  /// "closed" or "open" (persisted on the Pi).
  final String position;

  /// null when stopped, otherwise "opening" or "closing".
  final String? moving;

  const LidModel({required this.position, required this.moving});

  const LidModel.initial()
      : position = 'closed',
        moving = null;

  factory LidModel.fromJson(Map<String, dynamic> json) => LidModel(
        position: json['position'] as String? ?? 'closed',
        moving: json['moving'] as String?,
      );

  bool get isOpen => position == 'open';
  bool get isMoving => moving != null;
  bool get isOpening => moving == 'opening';
  bool get isClosing => moving == 'closing';

  /// Open only when the lid is closed and nothing is moving.
  bool get canOpen => !isOpen && !isMoving;

  /// Close whenever nothing is moving, so a lid that has been opened can
  /// always be closed again (also after a restart).
  bool get canClose => !isMoving;
}
