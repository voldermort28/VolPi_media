class UpdateInfo {
  final String latestVersion;
  final int buildNumber;
  final String changelog;
  final String apkUrl;
  final String ipaUrl;
  final String macosUrl;
  final String releaseUrl;
  final bool hasUpdate;
  final String currentVersion;

  UpdateInfo({
    required this.latestVersion,
    required this.buildNumber,
    required this.changelog,
    required this.apkUrl,
    required this.ipaUrl,
    this.macosUrl = '',
    this.releaseUrl = '',
    required this.hasUpdate,
    required this.currentVersion,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, String currentVer) {
    final latestVer = (json['version'] ?? json['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^[vV]'), '');
    final build = json['build'] is int ? json['build'] as int : int.tryParse(json['build']?.toString() ?? '0') ?? 0;
    final notes = (json['changelog'] ?? json['body'] ?? '').toString();

    String apk = (json['apkUrl'] ?? '').toString();
    String ipa = (json['ipaUrl'] ?? '').toString();
    String macos = (json['macosUrl'] ?? '').toString();
    String release = (json['html_url'] ?? 'https://stremio.laboon.vn/download').toString();

    // If GitHub release response, search in assets
    if (json['assets'] != null && json['assets'] is List) {
      for (var asset in json['assets']) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        final url = (asset['browser_download_url'] ?? '').toString();
        if (name.endsWith('.apk') && (apk.isEmpty || name.contains('androidtv'))) {
          apk = url;
        } else if (name.endsWith('.ipa') && (ipa.isEmpty || name.contains('ios'))) {
          ipa = url;
        } else if (name.endsWith('.zip') && (macos.isEmpty || name.contains('macos'))) {
          macos = url;
        }
      }
    }

    final hasNew = _isVersionNewer(latestVer, currentVer);

    return UpdateInfo(
      latestVersion: latestVer,
      buildNumber: build,
      changelog: notes.isNotEmpty ? notes : 'Bản cập nhật tối ưu hóa hiệu năng, cập nhật tính năng mới và vá lỗi.',
      apkUrl: apk,
      ipaUrl: ipa,
      macosUrl: macos,
      releaseUrl: release,
      hasUpdate: hasNew,
      currentVersion: currentVer,
    );
  }

  static bool _isVersionNewer(String remote, String current) {
    if (remote.isEmpty) return false;
    final cleanRemote = remote.replaceFirst(RegExp(r'^[vV]'), '').split('+')[0];
    final cleanCurrent = current.replaceFirst(RegExp(r'^[vV]'), '').split('+')[0];

    final remoteParts = cleanRemote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    while (remoteParts.length < 3) {
      remoteParts.add(0);
    }
    while (currentParts.length < 3) {
      currentParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (remoteParts[i] > currentParts[i]) return true;
      if (remoteParts[i] < currentParts[i]) return false;
    }
    return false;
  }
}
