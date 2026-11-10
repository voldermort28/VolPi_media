class GDriveSourceModel {
  final String id;
  final String name;
  final String folderId;
  final String url;
  final bool enabled;
  final bool isPrivate;
  final int count;
  final String? createdAt;

  const GDriveSourceModel({
    required this.id,
    required this.name,
    required this.folderId,
    required this.url,
    this.enabled = true,
    this.isPrivate = false,
    this.count = 0,
    this.createdAt,
  });

  factory GDriveSourceModel.fromJson(Map<String, dynamic> json) {
    return GDriveSourceModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Thư mục Google Drive',
      folderId: json['folderId'] as String? ?? '',
      url: json['url'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      isPrivate: json['isPrivate'] as bool? ?? false,
      count: (json['count'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String?,
    );
  }
}

class GDriveItemModel {
  final String id;
  final String name;
  final bool isFolder;
  final bool isAudio;
  final int size;
  final String formattedSize;
  final String mimeType;
  final String? thumbnailUrl;
  final String? subtitleFileId;
  final String? subtitleName;
  final String? folderId;
  final String? folderName;
  final String? folderPath;

  const GDriveItemModel({
    required this.id,
    required this.name,
    required this.isFolder,
    this.isAudio = false,
    this.size = 0,
    this.formattedSize = '',
    this.mimeType = '',
    this.thumbnailUrl,
    this.subtitleFileId,
    this.subtitleName,
    this.folderId,
    this.folderName,
    this.folderPath,
  });

  factory GDriveItemModel.fromJson(Map<String, dynamic> json) {
    final mime = json['mimeType'] as String? ?? '';
    final nameLower = (json['name'] as String? ?? '').toLowerCase();
    final isAud = json['isAudio'] == true ||
        mime.startsWith('audio/') ||
        ['.mp3', '.flac', '.m4a', '.wav', '.aac', '.ogg', '.dsf', '.wma', '.alac'].any((ext) => nameLower.endsWith(ext));

    return GDriveItemModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isFolder: json['isFolder'] as bool? ?? false,
      isAudio: isAud,
      size: (json['size'] as num?)?.toInt() ?? 0,
      formattedSize: json['formattedSize'] as String? ?? '',
      mimeType: mime,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      subtitleFileId: json['subtitleFileId'] as String?,
      subtitleName: json['subtitleName'] as String?,
      folderId: json['folderId'] as String?,
      folderName: json['folderName'] as String?,
      folderPath: json['folderPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isFolder': isFolder,
      'isAudio': isAudio,
      'size': size,
      'formattedSize': formattedSize,
      'mimeType': mimeType,
      'thumbnailUrl': thumbnailUrl,
      'subtitleFileId': subtitleFileId,
      'subtitleName': subtitleName,
      'folderId': folderId,
      'folderName': folderName,
      'folderPath': folderPath,
    };
  }
}

class GDriveFolderContentResult {
  final String folderId;
  final List<GDriveItemModel> folders;
  final List<GDriveItemModel> allFolders;
  final List<GDriveItemModel> videos;
  final List<GDriveItemModel> allVideos;
  final List<GDriveItemModel> audios;
  final List<GDriveItemModel> allAudios;
  final int totalVideos;
  final int totalAudios;
  final int totalFolders;
  final int totalItems;

  const GDriveFolderContentResult({
    required this.folderId,
    required this.folders,
    required this.allFolders,
    required this.videos,
    required this.allVideos,
    this.audios = const [],
    this.allAudios = const [],
    required this.totalVideos,
    this.totalAudios = 0,
    required this.totalFolders,
    required this.totalItems,
  });

  factory GDriveFolderContentResult.fromJson(Map<String, dynamic> json) {
    final folderList = (json['folders'] as List?)
            ?.map((e) => GDriveItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final allFolderList = (json['allFolders'] as List?)
            ?.map((e) => GDriveItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        folderList;
    final videoList = (json['videos'] as List?)
            ?.map((e) => GDriveItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final allVideoList = (json['allVideos'] as List?)
            ?.map((e) => GDriveItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        videoList;
    final audioList = (json['audios'] as List?)
            ?.map((e) => GDriveItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final allAudioList = (json['allAudios'] as List?)
            ?.map((e) => GDriveItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        audioList;

    return GDriveFolderContentResult(
      folderId: json['folderId'] as String? ?? '',
      folders: folderList,
      allFolders: allFolderList,
      videos: videoList,
      allVideos: allVideoList,
      audios: audioList,
      allAudios: allAudioList,
      totalVideos: (json['totalVideos'] as num?)?.toInt() ?? allVideoList.length,
      totalAudios: (json['totalAudios'] as num?)?.toInt() ?? allAudioList.length,
      totalFolders: (json['totalFolders'] as num?)?.toInt() ?? allFolderList.length,
      totalItems: (json['totalItems'] as num?)?.toInt() ?? (allVideoList.length + allAudioList.length + folderList.length),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'folderId': folderId,
      'folders': folders.map((e) => e.toJson()).toList(),
      'allFolders': allFolders.map((e) => e.toJson()).toList(),
      'videos': videos.map((e) => e.toJson()).toList(),
      'allVideos': allVideos.map((e) => e.toJson()).toList(),
      'audios': audios.map((e) => e.toJson()).toList(),
      'allAudios': allAudios.map((e) => e.toJson()).toList(),
      'totalVideos': totalVideos,
      'totalAudios': totalAudios,
      'totalFolders': totalFolders,
      'totalItems': totalItems,
    };
  }
}
