class FavoriteItem {
  final String id; // Unique ID (anime.id hoặc movie.id)
  final String title; // Tên phim / Anime
  final String poster; // URL poster ảnh bìa
  final String category; // 'anime' | 'secret'
  final String createdAt; // Thời điểm thêm vào yêu thích (ISO 8601)

  const FavoriteItem({
    required this.id,
    required this.title,
    this.poster = '',
    this.category = 'anime',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'poster': poster,
      'category': category,
      'createdAt': createdAt,
    };
  }

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      poster: json['poster']?.toString() ?? '',
      category: json['category']?.toString() ?? 'anime',
      createdAt: json['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }
}
