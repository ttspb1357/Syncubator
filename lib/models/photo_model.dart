/// Phototherapy light state from the Pi's `/status` payload (`photo`).
///
/// There is no light sensor: [isOn] is what the relay was last told to do.
class PhotoModel {
  final bool isOn;

  const PhotoModel({required this.isOn});

  const PhotoModel.initial() : isOn = false;

  factory PhotoModel.fromJson(Map<String, dynamic> json) =>
      PhotoModel(isOn: json['on'] as bool? ?? false);
}
