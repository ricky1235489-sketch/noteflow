"""和弦偵測器：從 MIDI 音符群偵測和弦根音與類型。"""
from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import pretty_midi

# 音名對照
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# 和弦模板（相對於根音的半音間距）
CHORD_TEMPLATES: dict[str, set[int]] = {
    "major": {0, 4, 7},
    "minor": {0, 3, 7},
    "dim": {0, 3, 6},
    "aug": {0, 4, 8},
    "sus4": {0, 5, 7},
    "sus2": {0, 2, 7},
    "7": {0, 4, 7, 10},
    "maj7": {0, 4, 7, 11},
    "m7": {0, 3, 7, 10},
}


@dataclass(frozen=True)
class Chord:
    """偵測到的和弦。"""
    root: int          # 根音 pitch class (0-11)
    quality: str       # major, minor, dim, etc.
    start_time: float
    end_time: float

    @property
    def root_name(self) -> str:
        return NOTE_NAMES[self.root]

    @property
    def name(self) -> str:
        suffix = "" if self.quality == "major" else self.quality
        return f"{self.root_name}{suffix}"

    def pitches_in_octave(self, octave: int) -> list[int]:
        """回傳指定八度的和弦音（MIDI pitch）。"""
        base = (octave + 1) * 12
        template = CHORD_TEMPLATES.get(self.quality, {0, 4, 7})
        return sorted(base + self.root + interval for interval in template)


class ChordDetector:
    """從 MIDI 音符偵測每個時間區段的和弦。"""

    def detect_chords(
        self,
        midi_data: "pretty_midi.PrettyMIDI",
        beats_per_measure: int = 4,
        tempo: float = 120.0,
    ) -> list[Chord]:
        """偵測每小節（或每拍）的和弦。

        策略：將時間切成小節，統計每個小節中各 pitch class 的出現時長，
        然後用模板匹配找出最佳和弦。
        """
        all_notes = []
        for instrument in midi_data.instruments:
            all_notes.extend(instrument.notes)

        if not all_notes:
            return []

        total_duration = max(n.end for n in all_notes)
        seconds_per_beat = 60.0 / tempo
        measure_duration = seconds_per_beat * beats_per_measure
        measure_count = max(1, int(total_duration / measure_duration) + 1)

        chords: list[Chord] = []

        for m in range(measure_count):
            start = m * measure_duration
            end = (m + 1) * measure_duration

            # 統計此小節中各 pitch class 的加權時長
            pitch_class_weight = [0.0] * 12
            for note in all_notes:
                if note.end <= start or note.start >= end:
                    continue
                overlap_start = max(note.start, start)
                overlap_end = min(note.end, end)
                duration = overlap_end - overlap_start
                pc = note.pitch % 12
                pitch_class_weight[pc] += duration

            # 找出最佳匹配的和弦
            best_chord = self._match_chord(pitch_class_weight, start, end)
            chords.append(best_chord)

        return chords

    def _match_chord(
        self, weights: list[float], start: float, end: float
    ) -> Chord:
        """用模板匹配找出最佳和弦。"""
        best_score = -1.0
        best_root = 0
        best_quality = "major"

        for root in range(12):
            for quality, template in CHORD_TEMPLATES.items():
                score = sum(
                    weights[(root + interval) % 12]
                    for interval in template
                )
                # 懲罰非和弦音
                non_chord_weight = sum(
                    weights[(root + i) % 12]
                    for i in range(12)
                    if i not in template
                )
                score -= non_chord_weight * 0.3

                # 偏好簡單和弦（major/minor）
                if quality in ("major", "minor"):
                    score *= 1.1

                if score > best_score:
                    best_score = score
                    best_root = root
                    best_quality = quality

        return Chord(
            root=best_root,
            quality=best_quality,
            start_time=start,
            end_time=end,
        )
