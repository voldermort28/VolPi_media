class AnimeModel {
  final String id;
  final String name;
  final String poster;
  final String background;
  final String description;
  final List<String> genres;
  final String type;
  final List<EpisodeModel> episodes;

  AnimeModel({
    required this.id,
    required this.name,
    required this.poster,
    required this.background,
    required this.description,
    this.genres = const [],
    this.type = 'series',
    this.episodes = const [],
  });

  factory AnimeModel.fromJson(Map<String, dynamic> json) {
    final List<String> genreList = [];
    if (json['genres'] != null) {
      for (final g in json['genres']) {
        genreList.add(g.toString());
      }
    }

    final List<EpisodeModel> eps = [];
    if (json['videos'] != null) {
      for (final v in json['videos']) {
        eps.add(EpisodeModel.fromJson(v));
      }
    }

    return AnimeModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      poster: json['poster'] ?? '',
      background: json['background'] ?? json['poster'] ?? '',
      description: json['description'] ?? '',
      genres: genreList,
      type: json['type'] ?? 'series',
      episodes: eps,
    );
  }

  AnimeModel copyWithEpisodes(List<EpisodeModel> newEpisodes) {
    return AnimeModel(
      id: id,
      name: name,
      poster: poster,
      background: background,
      description: description,
      genres: genres,
      type: type,
      episodes: newEpisodes,
    );
  }
}

class EpisodeModel {
  final String id;
  final int season;
  final int episode;
  final String title;
  final String thumbnail;
  final String overview;

  EpisodeModel({
    required this.id,
    required this.season,
    required this.episode,
    required this.title,
    required this.thumbnail,
    this.overview = '',
  });

  factory EpisodeModel.fromJson(Map<String, dynamic> json) {
    return EpisodeModel(
      id: json['id'] ?? '',
      season: json['season'] is int ? json['season'] : int.tryParse(json['season']?.toString() ?? '1') ?? 1,
      episode: json['episode'] is int ? json['episode'] : int.tryParse(json['episode']?.toString() ?? '1') ?? 1,
      title: json['title'] ?? json['name'] ?? 'Tập ${json['episode'] ?? 1}',
      thumbnail: json['thumbnail'] ?? '',
      overview: json['overview'] ?? '',
    );
  }
}
