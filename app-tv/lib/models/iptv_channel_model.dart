import 'match_model.dart';

class IptvChannelModel {
  final String id;
  final String name;
  final String logo;
  final String url;
  final String group;
  final Map<String, String> headers;
  final bool isPinned;
  final bool isHidden;

  const IptvChannelModel({
    required this.id,
    required this.name,
    this.logo = '',
    required this.url,
    this.group = 'Chung',
    this.headers = const {},
    this.isPinned = false,
    this.isHidden = false,
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
