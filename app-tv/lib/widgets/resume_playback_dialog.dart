import 'package:flutter/material.dart';
import '../models/watch_history_model.dart';
import 'tv_focusable_card.dart';

enum ResumeChoice {
  resume,      // Xem tiếp vị trí cũ
  restart,     // Xem lại từ đầu
  nextEpisode, // Xem tập tiếp theo
}

class ResumePlaybackDialog extends StatelessWidget {
  final WatchHistoryItem item;
  final bool? hasNextEpisode;
  final int? nextEpisodeNumber;

  const ResumePlaybackDialog({
    super.key,
    required this.item,
    this.hasNextEpisode,
    this.nextEpisodeNumber,
  });

  /// Trả về:
  /// - `ResumeChoice.resume`: Người dùng chọn "Xem tiếp"
  /// - `ResumeChoice.restart`: Người dùng chọn "Xem từ đầu"
  /// - `ResumeChoice.nextEpisode`: Người dùng chọn "Tập tiếp theo"
  /// - `null`: Người dùng bấm Hủy / Back
  static Future<ResumeChoice?> show(
    BuildContext context,
    WatchHistoryItem item, {
    bool? hasNextEpisode,
    int? nextEpisodeNumber,
  }) {
    return showDialog<ResumeChoice>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ResumePlaybackDialog(
        item: item,
        hasNextEpisode: hasNextEpisode,
        nextEpisodeNumber: nextEpisodeNumber,
      ),
    );
  }

  int? _resolveNextEpisode() {
    if (nextEpisodeNumber != null) return nextEpisodeNumber;
    if (hasNextEpisode == false) return null;

    if (item.episode > 0) return item.episode + 1;

    final idMatch = RegExp(r':ep:(\d+)').firstMatch(item.id) ??
        RegExp(r':\d+:(\d+)$').firstMatch(item.id);
    if (idMatch != null) {
      final cur = int.tryParse(idMatch.group(1)!);
      if (cur != null) return cur + 1;
    }

    final subMatch = RegExp(r'[Tt]ập\s*(\d+)').firstMatch(item.subtitle);
    if (subMatch != null) {
      final cur = int.tryParse(subMatch.group(1)!);
      if (cur != null) return cur + 1;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pctText = '${(item.progressPercent * 100).toInt()}%';
    final resolvedNextEp = _resolveNextEpisode();
    final bool showNextButton = (hasNextEpisode == true) || (hasNextEpisode == null && resolvedNextEp != null);
    final String nextLabel = resolvedNextEp != null ? 'Tập tiếp theo (Tập $resolvedNextEp)' : 'Tập tiếp theo';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: Container(
          width: showNextButton ? 470 : 440,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.history_rounded, color: Color(0xFF38BDF8), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Tiếp Tục Xem Phim',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Title & Subtitle
              Text(
                item.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 18),

              // Position & Progress Bar
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Đã xem đến: ${item.formattedPosition} / ${item.formattedDuration}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          pctText,
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: item.progressPercent,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF38BDF8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              if (showNextButton) ...[
                // Row 1: Nút Xem tiếp & Nút Tập tiếp theo
                Row(
                  children: [
                    Expanded(
                      child: TvFocusableCard(
                        autoFocus: true,
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).pop(ResumeChoice.resume),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Xem tiếp (${item.formattedPosition})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TvFocusableCard(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).pop(ResumeChoice.nextEpisode),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE50914), Color(0xFFDC2626)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE50914).withOpacity(0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.skip_next_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  nextLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Row 2: Nút Xem từ đầu
                TvFocusableCard(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).pop(ResumeChoice.restart),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.replay_rounded, color: Colors.white70, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Xem lại từ đầu',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Original 2-button layout for single movies / non-series
                Row(
                  children: [
                    Expanded(
                      child: TvFocusableCard(
                        autoFocus: true,
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).pop(ResumeChoice.resume),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Xem tiếp (${item.formattedPosition})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TvFocusableCard(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).pop(ResumeChoice.restart),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.replay_rounded, color: Colors.white70, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Xem từ đầu',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
