import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/playback_state.dart';
import 'playback_provider.dart';
import 'tempo_slider.dart';

class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar
              _ProgressBar(
                progress: playback.progressPercent,
                currentPosition: playback.currentPosition,
                totalDuration: playback.totalDuration,
                onSeek: (value) {
                  final position = Duration(
                    milliseconds:
                        (value * playback.totalDuration.inMilliseconds)
                            .round(),
                  );
                  notifier.seekTo(position);
                },
              ),
              const SizedBox(height: 4),
              // Transport controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Tempo control
                  TempoSlider(
                    tempo: playback.tempoMultiplier,
                    onChanged: notifier.setTempo,
                  ),
                  const Spacer(),
                  // Stop
                  IconButton(
                    icon: const Icon(Icons.stop),
                    iconSize: 32,
                    onPressed: playback.isStopped ? null : notifier.stop,
                  ),
                  const SizedBox(width: 8),
                  // Play / Pause
                  FilledButton(
                    onPressed: () {
                      if (playback.isPlaying) {
                        notifier.pause();
                      } else {
                        notifier.play();
                      }
                    },
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(16),
                    ),
                    child: Icon(
                      playback.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Measure info
                  Text(
                    '小節 ${playback.currentMeasure + 1}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  final Duration currentPosition;
  final Duration totalDuration;
  final ValueChanged<double> onSeek;

  const _ProgressBar({
    required this.progress,
    required this.currentPosition,
    required this.totalDuration,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: onSeek,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(currentPosition),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                _formatDuration(totalDuration),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
