import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/audio_player_handler.dart';
import 'tv_focusable_card.dart';

class MusicPlayerBottomSheet extends StatefulWidget {
  const MusicPlayerBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MusicPlayerBottomSheet(),
    );
  }

  @override
  State<MusicPlayerBottomSheet> createState() => _MusicPlayerBottomSheetState();
}

class _MusicPlayerBottomSheetState extends State<MusicPlayerBottomSheet> with SingleTickerProviderStateMixin {
  late AnimationController _vinylController;
  StreamSubscription<PlaybackState>? _stateSub;
  bool _showQueue = false;

  @override
  void initState() {
    super.initState();
    _vinylController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    final handler = VolPiAudioHandler.instance;
    if (handler.playbackState.value.playing) {
      _vinylController.repeat();
    }
    _stateSub = handler.playbackState.listen((state) {
      if (!mounted) return;
      if (state.playing && !_vinylController.isAnimating) {
        _vinylController.repeat();
      } else if (!state.playing && _vinylController.isAnimating) {
        _vinylController.stop();
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _vinylController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _extractAudioExt(String title) {
    final m = RegExp(r'\.(flac|mp3|m4a|wav|aac|ogg|opus|wma|alac)$', caseSensitive: false).firstMatch(title.trim());
    return m != null ? m.group(1)!.toUpperCase() : 'AUDIO';
  }

  String _cleanTitle(String title) {
    return title.replaceFirst(RegExp(r'\.(flac|mp3|m4a|wav|aac|ogg|opus|wma|alac)$', caseSensitive: false), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final handler = VolPiAudioHandler.instance;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 700;

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        if (item == null) return const SizedBox.shrink();

        final rawTitle = item.title;
        final title = _cleanTitle(rawTitle);
        final artist = item.artist ?? 'Nghệ sĩ';
        final album = item.album ?? 'Album';
        final artUri = item.artUri?.toString();
        final ext = _extractAudioExt(rawTitle);

        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data;
            final dur = item.duration ?? Duration.zero;

            return Container(
              height: size.height * (isMobile ? 0.90 : 0.85),
              decoration: const BoxDecoration(
                color: Color(0xFF141414),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: Color(0xFF262626), width: 1.5)),
              ),
              child: Column(
                children: [
                  // Top Drag Handle & Controls
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 28),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Column(
                          children: [
                            Text(
                              album,
                              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              'ĐANG PHÁT TỪ VOLPI MUSIC',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(
                            _showQueue ? Icons.queue_music_rounded : Icons.queue_music_outlined,
                            color: _showQueue ? const Color(0xFF38BDF8) : Colors.white70,
                            size: 24,
                          ),
                          onPressed: () => setState(() => _showQueue = !_showQueue),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: _showQueue
                        ? _buildQueueList(handler)
                        : StreamBuilder<Duration>(
                            stream: handler.player.positionStream,
                            initialData: state?.position ?? Duration.zero,
                            builder: (context, posSnap) {
                              final livePos = posSnap.data ?? (state?.position ?? Duration.zero);
                              return _buildPlayerContent(title, artist, artUri, ext, livePos, dur, state, handler, isMobile);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlayerContent(
    String title,
    String artist,
    String? artUri,
    String ext,
    Duration pos,
    Duration dur,
    PlaybackState? state,
    VolPiAudioHandler handler,
    bool isMobile,
  ) {
    final playing = state?.playing ?? false;
    final bufferedPos = state?.bufferedPosition ?? Duration.zero;
    final isBuffering = state?.processingState == AudioProcessingState.buffering ||
        state?.processingState == AudioProcessingState.loading;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 1),

          // Vinyl Record Artwork
          RotationTransition(
            turns: _vinylController,
            child: Container(
              width: isMobile ? 220 : 260,
              height: isMobile ? 220 : 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFF1E293B),
                    Color(0xFF0F172A),
                    Color(0xFF020617),
                  ],
                  stops: [0.3, 0.7, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withOpacity(0.25),
                    blurRadius: 36,
                    spreadRadius: 4,
                  ),
                ],
                border: Border.all(color: const Color(0xFF334155), width: 3),
              ),
              child: Center(
                child: Container(
                  width: isMobile ? 100 : 120,
                  height: isMobile ? 100 : 120,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0369A1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: artUri != null && artUri.isNotEmpty
                      ? CachedNetworkImage(imageUrl: artUri, fit: BoxFit.cover)
                      : const Icon(Icons.music_note_rounded, color: Colors.white, size: 48),
                ),
              ),
            ),
          ),

          const Spacer(flex: 1),

          // Quality Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
            ),
            child: Text(
              ext == 'FLAC' ? '✨ FLAC LOSSLESS' : '🎵 $ext HIGH QUALITY',
              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),

          const SizedBox(height: 12),

          // Track Title & Artist
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            artist,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 18),

          // Dual-Layer Seek Bar with Live Buffer
          Stack(
            alignment: Alignment.center,
            children: [
              // 1. Buffered Track Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: dur.inMilliseconds > 0
                        ? (bufferedPos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                        : 0.0,
                    minHeight: 4.0,
                    backgroundColor: const Color(0xFF1E293B),
                    valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF38BDF8).withOpacity(0.35)),
                  ),
                ),
              ),
              // 2. Interactive Position Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: const Color(0xFF38BDF8),
                  inactiveTrackColor: Colors.transparent, // Let buffered track shine through
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  min: 0,
                  max: dur.inMilliseconds.toDouble() > 0 ? dur.inMilliseconds.toDouble() : 1.0,
                  value: pos.inMilliseconds.toDouble().clamp(0.0, dur.inMilliseconds.toDouble() > 0 ? dur.inMilliseconds.toDouble() : 1.0),
                  onChanged: (val) {
                    handler.seek(Duration(milliseconds: val.toInt()));
                  },
                ),
              ),
            ],
          ),

          // Position / Buffer / Duration labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(pos), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                if (dur.inMilliseconds > 0 && bufferedPos.inMilliseconds > 0)
                  Text(
                    'Đã nạp: ${_formatDuration(bufferedPos)} (${((bufferedPos.inMilliseconds / dur.inMilliseconds) * 100).clamp(0, 100).toInt()}%)',
                    style: TextStyle(color: const Color(0xFF38BDF8).withOpacity(0.75), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                Text(_formatDuration(dur), style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Control Buttons (TV D-pad focusable + Shuffle & Repeat)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: handler.shuffleEnabledNotifier,
                builder: (_, isShuffle, __) => TvFocusableCard(
                  onTap: handler.toggleShuffle,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.shuffle_rounded,
                      size: 22,
                      color: isShuffle ? const Color(0xFF38BDF8) : Colors.white54,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TvFocusableCard(
                onTap: () => handler.skipToPrevious(),
                borderRadius: BorderRadius.circular(24),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.skip_previous_rounded, color: Colors.white, size: 34),
                ),
              ),
              const SizedBox(width: 14),
              TvFocusableCard(
                autoFocus: true,
                onTap: () => playing ? handler.pause() : handler.play(),
                borderRadius: BorderRadius.circular(36),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x660284C7),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: isBuffering
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(
                            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              TvFocusableCard(
                onTap: () => handler.skipToNext(),
                borderRadius: BorderRadius.circular(24),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.skip_next_rounded, color: Colors.white, size: 34),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<bool>(
                valueListenable: handler.repeatOneNotifier,
                builder: (_, isRepeat, __) => TvFocusableCard(
                  onTap: handler.toggleRepeatOne,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      isRepeat ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                      size: 22,
                      color: isRepeat ? const Color(0xFF38BDF8) : Colors.white54,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Volume Control Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: StreamBuilder<double>(
              stream: handler.volumeStream,
              initialData: handler.volume,
              builder: (context, volSnap) {
                final vol = volSnap.data ?? 1.0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          vol == 0
                              ? Icons.volume_off_rounded
                              : (vol < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                          color: const Color(0xFF38BDF8),
                          size: 20,
                        ),
                        splashRadius: 18,
                        onPressed: () {
                          handler.setVolume(vol == 0 ? 1.0 : 0.0);
                        },
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            activeTrackColor: const Color(0xFF38BDF8),
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: vol.clamp(0.0, 1.0),
                            min: 0.0,
                            max: 1.0,
                            onChanged: (newVol) => handler.setVolume(newVol),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 38,
                        child: Text(
                          '${(vol * 100).round()}%',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const Spacer(flex: 1),
        ],
      ),
    );
  }

  Widget _buildQueueList(VolPiAudioHandler handler) {
    return StreamBuilder<List<MediaItem>>(
      stream: handler.queue,
      builder: (context, snapshot) {
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return const Center(child: Text('Danh sách phát trống', style: TextStyle(color: Colors.white54)));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final track = list[index];
            final isCurrent = index == handler.currentIndex;

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TvFocusableCard(
                onTap: () => handler.skipToQueueItem(index),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCurrent ? const Color(0xFF0284C7).withOpacity(0.2) : const Color(0xFF1E293B).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCurrent ? const Color(0xFF38BDF8) : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isCurrent ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: isCurrent
                              ? const Icon(Icons.equalizer_rounded, color: Colors.white, size: 18)
                              : Text('${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _cleanTitle(track.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? const Color(0xFF38BDF8) : Colors.white,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              track.artist ?? 'Nghệ sĩ',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
