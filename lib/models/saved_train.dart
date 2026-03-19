import 'dart:convert';

class SavedTrain {
  final String id;
  final String name;
  final String deviceName;
  final DateTime? lastConnected;

  SavedTrain({
    required this.id,
    required this.name,
    required this.deviceName,
    this.lastConnected,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'deviceName': deviceName,
    'lastConnected': lastConnected?.toIso8601String(),
  };

  factory SavedTrain.fromJson(Map<String, dynamic> json) => SavedTrain(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    deviceName: json['deviceName'] as String? ?? '',
    lastConnected: json['lastConnected'] != null
        ? DateTime.tryParse(json['lastConnected'] as String)
        : null,
  );

  static String encodeList(List<SavedTrain> trains) =>
      jsonEncode(trains.map((t) => t.toJson()).toList());

  static List<SavedTrain> decodeList(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((e) => SavedTrain.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}