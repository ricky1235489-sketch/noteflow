import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';

class TempoSlider extends StatelessWidget {
  final double tempo;
  final ValueChanged<double> onChanged;

  const TempoSlider({
    super.key,
    required this.tempo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.speed, size: 18, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              value: tempo,
              min: AppConstants.minTempoMultiplier,
              max: AppConstants.maxTempoMultiplier,
              divisions: 7,
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          '${tempo.toStringAsFixed(2)}x',
          style: theme.textTheme.bodySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
