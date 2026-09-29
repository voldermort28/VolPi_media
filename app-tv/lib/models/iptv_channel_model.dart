import 'match_model.dart';

class IptvSourceModel {
  final String id;
  final String name;
  final int count;

  const IptvSourceModel({
    required this.id,
    required this.name,
    this.count = 0,
  });

  factory IptvSourceModel.fromJson(Map<String, dynamic> json) {
    return IptvSourceModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Nguồn',
      count: json['count'] is int ? json['count'] : 0,
    );
  }
}

class IptvChannelModel {
  final String id;
  final String name;
  final String logo;
  final String url;
  final String group;
  final Map<String, String> headers;
  final bool isPinned;
  final bool isHidden;
  final String sourceId;
  final String sourceName;

  const IptvChannelModel({
    required this.id,
    required this.name,
    this.logo = '',
    required this.url,
    this.group = 'Chung',
    this.headers = const {},
    this.isPinned = false,
    this.isHidden = false,
    this.sourceId = 'pl-default',
    this.sourceName = 'Kênh Quốc Gia',
  });

  factory IptvChannelModel.fromJson(Map<String, dynamic> json) {
    Map<String, String> parsedHeaders = {};
    if (json['headers'] is Map) {
      (json['headers'] as Map).forEach((k, v) {
        if (k != null && v != null) {
          parsedHeaders[k.toString()] = v.toString();
        }
      });
    }

    return IptvChannelModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Kênh truyền hình',
      logo: json['logo']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      group: json['group']?.toString() ?? 'Chung',
      headers: parsedHeaders,
      isPinned: json['isPinned'] == true,
      isHidden: json['isHidden'] == true,
      sourceId: json['sourceId']?.toString() ?? 'pl-default',
      sourceName: json['sourceName']?.toString() ?? 'Kênh Quốc Gia',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'logo': logo,
      'url': url,
      'group': group,
      'headers': headers,
      'isPinned': isPinned,
      'isHidden': isHidden,
      'sourceId': sourceId,
      'sourceName': sourceName,
    };
  }

  /// Converts this channel to a StreamChannel for VideoPlayerScreen
  StreamChannel toStreamChannel() {
    return StreamChannel(
      name: group,
      title: name,
      url: url,
      headers: headers,
    );
  }
}
