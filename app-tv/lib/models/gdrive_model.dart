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
    return GDriveItemModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isFolder: json['isFolder'] as bool? ?? false,
      size: (json['size'] as num?)?.toInt() ?? 0,
      formattedSize: json['formattedSize'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      subtitleFileId: json['subtitleFileId'] as String?,
      subtitleName: json['subtitleName'] as String?,
      folderId: json['folderId'] as String?,
      folderName: json['folderName'] as String?,
      folderPath: json['folderPath'] as String?,
    );
  }
}

class GDriveFolderContentResult {
  final String folderId;
  final List<GDriveItemModel> folders;
  final List<GDriveItemModel> allFolders;
  final List<GDriveItemModel> videos;
  final List<GDriveItemModel> allVideos;
  final int totalVideos;
  final int totalFolders;
  final int totalItems;

  const GDriveFolderContentResult({
    required this.folderId,
    required this.folders,
    required this.allFolders,
    required this.videos,
    required this.allVideos,
    required this.totalVideos,
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

    return GDriveFolderContentResult(
      folderId: json['folderId'] as String? ?? '',
      folders: folderList,
      allFolders: allFolderList,
      videos: videoList,
      allVideos: allVideoList,
      totalVideos: (json['totalVideos'] as num?)?.toInt() ?? allVideoList.length,
      totalFolders: (json['totalFolders'] as num?)?.toInt() ?? allFolderList.length,
      totalItems: (json['totalItems'] as num?)?.toInt() ?? (allVideoList.length + folderList.length),
    );
  }
}
