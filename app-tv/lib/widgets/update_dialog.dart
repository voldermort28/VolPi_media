import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/update_model.dart';
import '../services/update_service.dart';
import 'tv_focusable_card.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  static Future<void> show(BuildContext context, UpdateInfo info) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _progressText = '';
  String? _errorMessage;

  Future<void> _startUpdate() async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _progressText = 'Đang chuẩn bị tải...';
    });

    if (Platform.isAndroid) {
      final success = await UpdateService.downloadAndInstallApk(
        downloadUrl: widget.updateInfo.apkUrl,
        onProgress: (progress, received, total) {
          if (mounted) {
            setState(() {
              _progress = progress;
              final recMB = (received / 1024 / 1024).toStringAsFixed(1);
              final totalMB = (total / 1024 / 1024).toStringAsFixed(1);
              final pct = (progress * 100).toInt();
              _progressText = '$pct% ($recMB MB / $totalMB MB)';
            });
          }
        },
      );

      if (!success && mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Không thể mở file cài đặt. Vui lòng thử lại.';
        });
      }
    } else if (Platform.isIOS) {
      // iOS with TrollStore 1-click in-place update
      final success = await UpdateService.installIpaTrollStore(widget.updateInfo.ipaUrl);
      if (mounted) {
        if (success) {
          Navigator.of(context).pop();
        } else {
          setState(() {
            _isDownloading = false;
            _errorMessage = 'Không thể mở TrollStore. Đang chuyển sang trình duyệt...';
          });
        }
      }
    } else {
      // macOS / Desktop platforms
      final targetUrl = widget.updateInfo.releaseUrl.isNotEmpty
          ? widget.updateInfo.releaseUrl
          : 'https://stremio.laboon.vn/download';
      final uri = Uri.parse(targetUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.updateInfo;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: Container(
          width: 520,
          constraints: const BoxConstraints(maxHeight: 560),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0284C7).withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CẬP NHẬT ỨNG DỤNG',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'v${info.currentVersion}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(Icons.arrow_forward_rounded, color: Color(0xFF38BDF8), size: 14),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF38BDF8), width: 0.8),
                              ),
                              child: Text(
                                'v${info.latestVersion}',
                                style: const TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Text(
                'Nội dung cập nhật:',
                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              // Changelog Box
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      info.changelog,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),

              // Download Progress Bar (When downloading)
              if (_isDownloading) ...[
                const SizedBox(height: 18),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Đang tải bản cập nhật...',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          _progressText,
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 8,
                        backgroundColor: const Color(0xFF1E293B),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                      ),
                    ),
                  ],
                ),
              ],

              // Error Notice
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],

              const SizedBox(height: 22),

              // Action Buttons (D-Pad remote friendly)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_isDownloading)
                    TvFocusableCard(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        color: const Color(0xFF1E293B),
                        child: const Text(
                          'Để sau',
                          style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  TvFocusableCard(
                    onTap: _isDownloading ? () {} : _startUpdate,
                    autoFocus: true,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: _isDownloading
                            ? const LinearGradient(colors: [Color(0xFF334155), Color(0xFF475569)])
                            : const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF38BDF8)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isDownloading ? Icons.hourglass_top_rounded : Icons.download_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isDownloading
                                ? 'Đang cập nhật...'
                                : Platform.isIOS
                                    ? 'Cài qua TrollStore'
                                    : Platform.isAndroid
                                        ? 'Cập nhật ngay'
                                        : 'Tải bản mới',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
