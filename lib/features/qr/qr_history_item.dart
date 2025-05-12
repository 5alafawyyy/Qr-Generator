class QRHistoryItem {
  final String data;
  final String? imagePath;
  final String? logoPath;
  QRHistoryItem({required this.data, this.imagePath, this.logoPath});

  Map<String, dynamic> toJson() => {
    'data': data,
    'imagePath': imagePath,
    'logoPath': logoPath,
  };
  factory QRHistoryItem.fromJson(Map<String, dynamic> json) => QRHistoryItem(
    data: json['data'],
    imagePath: json['imagePath'],
    logoPath: json['logoPath'],
  );
}
