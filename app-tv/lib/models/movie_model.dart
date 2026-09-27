class MovieModel {
  final String id;
  final String rawId;
  final String title;
  final String poster;
  final String ribbon;
  final String description;
  final List<String> genres;
  final List<String> cast;

  MovieModel({
    required this.id,
    required this.rawId,
    required this.title,
    required this.poster,
    this.ribbon = '',
    this.description = '',
    this.genres = const [],
    this.cast = const [],
  });

  factory MovieModel.fromJson(Map<String, dynamic> json) {
    final String fullId = json['id'] ?? '';
    final String raw = json['rawId'] ?? fullId.replaceFirst('vlxx:', '');

    final List<String> genreList = [];
    if (json['genres'] != null) {
      for (final g in json['genres']) {
        genreList.add(g.toString());
      }
    }

    final List<String> castList = [];
    if (json['cast'] != null) {
      for (final c in json['cast']) {
        castList.add(c.toString());
      }
    }

    return MovieModel(
      id: fullId,
      rawId: raw,
      title: json['name'] ?? json['title'] ?? 'Phim $raw',
      poster: json['poster'] ?? '',
      ribbon: json['ribbon'] ?? '',
      description: json['description'] ?? '',
      genres: genreList,
      cast: castList,
    );
  }
}
