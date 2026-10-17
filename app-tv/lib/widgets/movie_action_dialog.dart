import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'tv_focusable_card.dart';

enum MovieAction {
  play,
  toggleFavorite,
  removeHistory,
  cancel,
}

class MovieActionDialog extends StatelessWidget {
  final String title;
  final String poster;
  final bool isFavorite;
  final bool hasHistory;

  const MovieActionDialog({
    super.key,
    required this.title,
    this.poster = '',
    required this.isFavorite,
    required this.hasHistory,
  });

  static Future<MovieAction?> show(
    BuildContext context, {
    required String title,
    String poster = '',
    required bool isFavorite,
    required bool hasHistory,
  }) {
    return showDialog<MovieAction>(
      context: context,
      barrierDismissible: true,
      builder: (_) => MovieActionDialog(
        title: title,
        poster: poster,
        isFavorite: isFavorite,
        hasHistory: hasHistory,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.7),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with mini poster and title
              Row(
                children: [
                  if (poster.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: poster,
                        width: 50,
                        height: 70,
                        memCacheWidth: 60,
                        memCacheHeight: 80,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 50,
                          height: 70,
                          color: const Color(0xFF334155),
                          child: const Icon(Icons.movie_outlined, color: Colors.white30, size: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tùy chọn phim',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 1. Nút Thêm / Xóa Yêu thích (Auto-focus cho remote TV)
              TvFocusableCard(
                autoFocus: true,
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).pop(MovieAction.toggleFavorite),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isFavorite ? const Color(0xFF831843) : const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFavorite ? const Color(0xFFF43F5E) : Colors.white12,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isFavorite ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                        color: isFavorite ? const Color(0xFFFB7185) : Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isFavorite ? 'Xóa khỏi Danh Sách Yêu Thích' : 'Thêm vào Danh Sách Yêu Thích',
                          style: TextStyle(
                            color: isFavorite ? const Color(0xFFFECDD3) : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Nút Xóa khỏi Lịch sử đã xem (nếu phim đã có trong lịch sử)
              if (hasHistory) ...[
                const SizedBox(height: 10),
                TvFocusableCard(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).pop(MovieAction.removeHistory),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: Colors.amberAccent, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Xóa khỏi Danh Sách Đã Xem',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // 3. Nút Phát Phim
              const SizedBox(height: 10),
              TvFocusableCard(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).pop(MovieAction.play),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4), width: 1),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.play_circle_outline_rounded, color: Color(0xFF38BDF8), size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Phát Phim Ngay',
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Nút Đóng
              const SizedBox(height: 10),
              TvFocusableCard(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).pop(MovieAction.cancel),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.close_rounded, color: Colors.white60, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Đóng',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
